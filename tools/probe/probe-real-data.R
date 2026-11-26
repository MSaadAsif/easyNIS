#!/usr/bin/env Rscript

source(file.path("tools", "probe", "probe-modules.R"))
loop_dir <- probe_workspace()
data_dir <- Sys.getenv("EASYNIS_DATA", unset = "")
if (!dir.exists(data_dir)) {
  stop("EASYNIS_DATA must point to the local NIS data directory.")
}
run_dir <- probe_run_directory(loop_dir, "real-data")
source(file.path("tools", "probe", "record-probe.R"))
recorder <- new_probe_recorder(run_dir)
duckdb_config <- getOption("easyNIS.duckdb_config", list())
duckdb_config$temp_directory <- file.path(run_dir, "private")
options(easyNIS.duckdb_config = duckdb_config)
record_step <- recorder$record
devtools::load_all(".", quiet = TRUE)

years <- easyNIS:::nis_open_available_years(data_dir)
if (!length(years)) {
  stop("No annual or Hive NIS Parquet parts found in EASYNIS_DATA.")
}
for (year in years) {
  record_step("open_year", "nis_open + collect", year, function() {
    easyNIS::nis_open(data_dir, years = year) |>
      dplyr::transmute(.nis_probe_row = 1L) |>
      utils::head(1L) |>
      dplyr::collect()
  })
}

year <- max(years)
query <- record_step("open_latest_for_workflows", "nis_open", year, function() {
  easyNIS::nis_open(data_dir, years = year)
})
record_step("ami_with_pci_cohort", "nis_flag_dx + nis_flag_pr", year, function() {
  query |>
    easyNIS::nis_flag_dx(ami = "I21") |>
    easyNIS::nis_flag_pr(pci = c("027", "02C")) |>
    dplyr::filter(ami, pci) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
record_step("sepsis_mortality_cohort", "nis_flag_dx", year, function() {
  query |>
    easyNIS::nis_flag_dx(sepsis = c("A40", "A41")) |>
    dplyr::filter(sepsis) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
record_step("hocm_cohort", "nis_flag_dx", year, function() {
  query |>
    easyNIS::nis_flag_dx(hocm = "I421") |>
    dplyr::filter(hocm) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
design <- record_step("survey_design", "nis_design", year, function() {
  flagged <- query |> easyNIS::nis_flag_dx(ami = "I21")
  diagnosis_fields <- easyNIS:::nis_diagnosis_fields(query)
  easyNIS::nis_design(flagged, cohort = ami, keep = c(AGE, FEMALE, DIED, TOTCHG, CCR_NIS, HOSP_NIS, diagnosis_fields))
})
record_step(
  "weighted_descriptives",
  "srvyr::survey_total + srvyr::survey_mean",
  year,
  function() {
    srvyr::summarise(design, discharges = srvyr::survey_total(), mean_age = srvyr::survey_mean(AGE, na.rm = TRUE))
  },
  private_summary = numeric_probe_summary
)
record_step(
  "regression",
  "survey::svyglm",
  year,
  function() {
    survey::svyglm(DIED ~ AGE + FEMALE, design = design, family = stats::quasibinomial())
  },
  private_summary = function(model) summary(model)$coefficients
)
record_step("suppression", "nis_cell_counts + nis_suppress", year, function() {
  counts <- easyNIS::nis_cell_counts(design, by = "FEMALE")
  easyNIS::nis_suppress(counts, count_col = "n", by = "FEMALE", hospital_col = "hospitals")
})
record_step("cost", "nis_cost", year, function() {
  costs <- design$variables |>
    dplyr::filter(.in_cohort) |>
    dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
    easyNIS::nis_cost(dollars = min(2024L, max(years)))
  list(data = costs, provenance = easyNIS::nis_cost_provenance(costs))
})
record_step("comorbidity", "nis_comorbidity", year, function() {
  comorbidity_fields <- easyNIS:::nis_diagnosis_fields(design$variables)
  rows <- design$variables |>
    dplyr::filter(.in_cohort) |>
    dplyr::select(dplyr::all_of(comorbidity_fields)) |>
    dplyr::collect()
  easyNIS::nis_comorbidity(rows)
})
transition_years <- years[years >= 2016L]
record_step("code_transitions", "nis_audit_code_transition", transition_years, function() {
  transition_query <- easyNIS::nis_open(data_dir, years = transition_years)
  easyNIS::nis_audit_code_transition(transition_query, codes = c(ami = "I21", heart_failure = "I50"), type = "dx")
})
record_step("trend_2016_to_latest", "nis_design + srvyr::survey_mean", transition_years, function() {
  trend <- easyNIS::nis_open(data_dir, years = transition_years)
  trend <- trend |> easyNIS::nis_flag_dx(sepsis = c("A40", "A41"))
  trend_design <- easyNIS::nis_design(trend, cohort = sepsis, keep = c(YEAR, DIED))
  trend_design |>
    dplyr::mutate(.died = as.integer(DIED == "Yes")) |>
    dplyr::group_by(YEAR) |>
    srvyr::summarise(mortality = srvyr::survey_mean(.died, na.rm = TRUE))
})
failed_steps <- recorder$finish()
if (length(failed_steps)) {
  cat(paste(failed_steps, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
