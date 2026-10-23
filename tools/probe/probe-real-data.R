#!/usr/bin/env Rscript

source(file.path("tools", "probe", "helpers.R"))
main_repo <- find_main_repo()
read_main_renviron(main_repo)
loop_dir <- Sys.getenv("EASYNIS_LOOP_DIR", unset = file.path(main_repo, "local", "loop"))
loop_dir <- resolve_loop_dir(main_repo, loop_dir)
data_dir <- Sys.getenv("EASYNIS_DATA", unset = "")
if (!dir.exists(data_dir)) stop("EASYNIS_DATA must point to the local NIS data directory.")
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S")
run_dir <- file.path(loop_dir, stamp)
private_dir <- file.path(run_dir, "private")
dir.create(private_dir, recursive = TRUE)
findings_file <- file.path(run_dir, "findings.jsonl")
private_file <- file.path(private_dir, "sanity-checks.rds")
private_conditions_file <- file.path(private_dir, "condition-details.rds")
invisible(file.create(findings_file))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install jsonlite to write probe findings.")
devtools::load_all(".", quiet = TRUE)

findings <- list()
private_estimates <- list()
private_condition_details <- list()
record_step <- function(step, year = NA_integer_, fun) {
  function_name <- switch(step,
    open_year = "nis_open",
    open_latest_for_workflows = "nis_open",
    ami_with_pci_cohort = "nis_flag_dx + nis_flag_pr",
    sepsis_mortality_cohort = "nis_flag_dx",
    hocm_cohort = "nis_flag_dx",
    survey_design = "nis_design",
    weighted_descriptives = "srvyr::survey_total + srvyr::survey_mean",
    regression = "survey::svyglm",
    suppression = "nis_cell_counts + nis_suppress",
    cost = "nis_cost",
    comorbidity = "nis_comorbidity",
    code_transitions = "nis_audit_code_transition",
    trend_2016_to_latest = "nis_design + srvyr::survey_mean",
    step
  )
  conditions <- list()
  capture_condition <- function(condition, kind) {
    private_condition_details[[length(private_condition_details) + 1L]] <<- list(
      step = step,
      condition_type = kind,
      condition_class = class(condition),
      calling_function = function_name,
      message = conditionMessage(condition)
    )
    conditions[[length(conditions) + 1L]] <<- safe_condition_record(condition, function_name)
    invisible(NULL)
  }
  started <- proc.time()[["elapsed"]]
  gc(reset = TRUE)
  result <- tryCatch(withCallingHandlers(fun(),
    warning = function(w) { capture_condition(w, "warning"); invokeRestart("muffleWarning") },
    message = function(m) { capture_condition(m, "message"); invokeRestart("muffleMessage") }
  ), error = identity)
  elapsed <- unname(proc.time()[["elapsed"]] - started)
  memory <- tryCatch({
    peak <- gc()[, "max used"]
    cell_bytes <- if (.Machine$sizeof.pointer == 8L) 56 else 32
    (peak[["Ncells"]] * cell_bytes + peak[["Vcells"]] * .Machine$sizeof.pointer) / 1024^2
  }, error = function(e) NA_real_)
  failed <- inherits(result, "error")
  if (failed) capture_condition(result, "error")
  finding <- list(
    step = step, function_name = function_name, year = year,
    pass = !failed, conditions = conditions,
    elapsed_seconds = elapsed, peak_r_heap_mb_estimate = as.numeric(memory)
  )
  findings[[length(findings) + 1L]] <<- finding
  connection <- file(findings_file, open = "a")
  writeLines(jsonlite::toJSON(finding, auto_unbox = TRUE, null = "null",
    na = "null", dataframe = "rows", digits = NA), connection, useBytes = TRUE)
  close(connection)
  if (!failed && step %in% c("weighted_descriptives", "regression")) {
    private_estimates[[step]] <<- private_sanity_summary(step, result)
  }
  invisible(result)
}

files <- list.files(data_dir, pattern = "^NIS_[0-9]{4}[.]parquet$", full.names = TRUE)
years <- sort(as.integer(sub("^NIS_([0-9]{4})[.]parquet$", "\\1", basename(files))))
if (!length(years)) stop("No NIS_<year>.parquet files found in EASYNIS_DATA.")
for (year in years) {
  record_step("open_year", year, function() easyNIS::nis_open(data_dir, years = year))
}

year <- max(years)
query <- NULL
record_step("open_latest_for_workflows", year, function() {
  query <<- easyNIS::nis_open(data_dir, years = year)
  query
})
record_step("ami_with_pci_cohort", year, function() {
  query |>
    easyNIS::nis_flag_dx(ami = "I21") |>
    easyNIS::nis_flag_pr(pci = c("027", "02C")) |>
    dplyr::filter(ami, pci) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
record_step("sepsis_mortality_cohort", year, function() {
  query |>
    easyNIS::nis_flag_dx(sepsis = c("A40", "A41")) |>
    dplyr::filter(sepsis) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
record_step("hocm_cohort", year, function() {
  query |>
    easyNIS::nis_flag_dx(hocm = "I421") |>
    dplyr::filter(hocm) |>
    dplyr::summarise(matched_rows = dplyr::n()) |>
    dplyr::collect()
})
design <- NULL
record_step("survey_design", year, function() {
  flagged <- query |> easyNIS::nis_flag_dx(ami = "I21")
  diagnosis_fields <- easyNIS:::probe_diagnosis_columns(query)
  design <<- easyNIS::nis_design(flagged, cohort = ami,
    keep = c(AGE, FEMALE, DIED, TOTCHG, CCR_NIS, HOSP_NIS, diagnosis_fields))
  design
})
record_step("weighted_descriptives", year, function() {
  srvyr::summarise(design,
    discharges = srvyr::survey_total(),
    mean_age = srvyr::survey_mean(AGE, na.rm = TRUE))
})
record_step("regression", year, function() {
  survey::svyglm(DIED ~ AGE + FEMALE, design = design,
    family = stats::quasibinomial())
})
record_step("suppression", year, function() {
  counts <- easyNIS::nis_cell_counts(design, by = "FEMALE")
  easyNIS::nis_suppress(counts, count_col = "n", by = "FEMALE",
    hospital_col = "hospitals")
})
record_step("cost", year, function() {
  costs <- design$variables |>
    dplyr::filter(.in_cohort) |>
    dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
    easyNIS::nis_cost(dollars = min(2024L, max(years)))
  list(data = costs, provenance = easyNIS::nis_cost_provenance(costs))
})
record_step("comorbidity", year, function() {
  comorbidity_fields <- grep("^(?:I10_DX|DXPOA)[0-9]+$", names(design$variables),
    value = TRUE, perl = TRUE)
  rows <- design$variables |>
    dplyr::filter(.in_cohort) |>
    dplyr::select(dplyr::all_of(comorbidity_fields)) |>
    dplyr::collect()
  easyNIS::nis_comorbidity(rows)
})
transition_years <- intersect(2016:max(years), years)
record_step("code_transitions", transition_years, function() {
  transition_query <- easyNIS::nis_open(data_dir, years = transition_years)
  easyNIS::nis_audit_code_transition(transition_query,
    codes = c(ami = "I21", heart_failure = "I50"), type = "dx")
})
trend <- NULL
trend_years <- intersect(2016:max(years), years)
record_step("trend_2016_to_latest", trend_years, function() {
  trend <<- easyNIS::nis_open(data_dir, years = trend_years)
  trend <- trend |> easyNIS::nis_flag_dx(sepsis = c("A40", "A41"))
  trend_design <- easyNIS::nis_design(trend, cohort = sepsis,
    keep = c(YEAR, DIED))
  trend_design |>
    dplyr::mutate(.died = as.integer(DIED == "Yes")) |>
    dplyr::group_by(YEAR) |>
    srvyr::summarise(mortality = srvyr::survey_mean(.died, na.rm = TRUE))
})
saveRDS(private_estimates, private_file)
saveRDS(private_condition_details, private_conditions_file)
failed_steps <- unique(vapply(Filter(function(finding) !isTRUE(finding$pass), findings),
  `[[`, character(1), "step"))
if (length(failed_steps)) {
  cat(paste(failed_steps, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
