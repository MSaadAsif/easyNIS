#!/usr/bin/env Rscript

source(".agents/skills/verify/runner.R")
source(".agents/skills/verify/study.R")

write_evidence <- function(x, path, digits = 12L) {
  print(x, digits = digits)
  dput(x, file = path)
}

write_parquet <- function(data, path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "fixture", data)
  sql_path <- DBI::dbQuoteString(con, path)
  DBI::dbExecute(con, paste("COPY fixture TO", sql_path, "(FORMAT PARQUET)"))
}

annual_fixture <- function(scratch, evidence) {
  records <- data.frame(
    key = 1:8, YEAR = rep(2019:2020, each = 4L),
    HOSP_NIS = rep(c(1L, 1L, 2L, 2L), 2L), NIS_STRATUM = 1L,
    DISCWT = c(2, 3, 4, 5, 6, 7, 8, 9), AGE = c(55, 60, 65, 70, 75, 80, 85, 90),
    TOTCHG = 1000, CCR_NIS = 0.25,
    I10_DX1 = rep(c("I501", "Z515", "I502", "Z515"), 2L),
    I10_DX2 = rep(c(NA, "I509", NA, NA), 2L),
    I10_PR1 = rep("02UG0JZ", 8L), PRDAY1 = 1L,
    I10_PR2 = rep(c("0JH604Z", "0JH604Z", "0JH604Z", NA), 2L),
    PRDAY2 = rep(c(3L, NA_integer_, 0L, NA_integer_), 2L)
  )
  path <- file.path(scratch, "annual")
  stopifnot(dir.create(path))
  dput(records, file = file.path(evidence, "annual-input.R"))
  write_parquet(records[records$YEAR == 2019L, ], file.path(path, "NIS_2019.parquet"))
  hive <- file.path(path, "YEAR=2020")
  stopifnot(dir.create(hive))
  write_parquet(records[records$YEAR == 2020L, setdiff(names(records), "YEAR")],
    file.path(hive, "part.parquet"))
  path
}

drive_open <- function(scratch, evidence) {
  path <- annual_fixture(scratch, evidence)
  spill_root <- file.path(scratch, "spill")
  stopifnot(dir.create(spill_root))
  old <- options(easyNIS.duckdb_config = list(temp_directory = spill_root, threads = 2L))
  on.exit(options(old))
  data <- easyNIS::nis_open(path, check_release = FALSE)
  stopifnot(inherits(data, "tbl_sql"), length(list.files(spill_root)) == 1L)
  counts <- data |>
    dplyr::count(YEAR) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  selected <- easyNIS::nis_open(path, years = 2020L, check_release = FALSE) |>
    dplyr::summarise(rows = dplyr::n(), key_sum = sum(key, na.rm = TRUE)) |>
    dplyr::collect()
  stopifnot(identical(counts$YEAR, 2019:2020), all(as.numeric(counts$n) == 4),
    as.numeric(selected$rows) == 4, as.numeric(selected$key_sum) == 26)
  rm(data)
  gc()
  stopifnot(!length(list.files(spill_root)))
  write_evidence(list(counts = counts, selected = selected, spill_removed = TRUE),
    file.path(evidence, "results.R"))
}

drive_cohort <- function(scratch, evidence) {
  data <- easyNIS::nis_open(annual_fixture(scratch, evidence), check_release = FALSE)
  flagged <- data |>
    easyNIS::nis_flag_dx(principal = "I50", position = "principal") |>
    easyNIS::nis_flag_dx(any_dx = "I50") |>
    easyNIS::nis_flag_pr(device = "0JH60") |>
    easyNIS::nis_flag_pr_timing("02UG0", "0JH60", relation = "after",
      missing_day = "indeterminate")
  stopifnot(inherits(flagged, "tbl_sql"))
  rows <- flagged |>
    dplyr::select(key, principal, any_dx, device, outcome_post_index) |>
    dplyr::arrange(key) |>
    dplyr::collect()
  attrition <- easyNIS::nis_attrition(flagged, diagnosed = any_dx, post = outcome_post_index)
  stopifnot(
    identical(rows$principal, rep(c(TRUE, FALSE, TRUE, FALSE), 2L)),
    identical(rows$any_dx, rep(c(TRUE, TRUE, TRUE, FALSE), 2L)),
    identical(rows$device, rep(c(TRUE, TRUE, TRUE, FALSE), 2L)),
    identical(rows$outcome_post_index, rep(c(TRUE, NA, FALSE, FALSE), 2L)),
    identical(attrition$n_unweighted, c(8L, 6L, 2L))
  )
  write_evidence(list(rows = rows, attrition = attrition), file.path(evidence, "results.R"))
}

drive_survey <- function(scratch, evidence) {
  data <- easyNIS::nis_open(annual_fixture(scratch, evidence), check_release = FALSE) |>
    easyNIS::nis_flag_dx(eligible = "I50", position = "principal")
  design <- easyNIS::nis_design(data, eligible, keep = c(AGE, TOTCHG, CCR_NIS),
    annualize = TRUE, dollars = 2020L)
  provenance <- easyNIS::nis_cost_provenance(design)
  base <- srvyr::summarise(design, total = srvyr::survey_total())
  reweighted <- easyNIS::nis_reweight(design, rep(2, length(stats::weights(design))))
  adjusted <- srvyr::summarise(reweighted, total = srvyr::survey_total())
  stopifnot(nrow(design$variables) == 4L, base$total == 10, adjusted$total == 20,
    is.finite(base$total_se), adjusted$total_se == 2 * base$total_se,
    identical(provenance$base_year, 2020L),
    all(design$variables$cost_adj[design$variables$YEAR == 2020L] == 250))
  write_evidence(list(base = base, reweighted = adjusted, cost = provenance),
    file.path(evidence, "results.R"))
}

drive_disclosure <- function(scratch, evidence) {
  rows <- easyNIS::nis_open(annual_fixture(scratch, evidence), check_release = FALSE) |>
    dplyr::mutate(category = dplyr::case_when(
      key == 1L ~ "small",
      key %in% c(2L, 5L, 6L) ~ "companion",
      TRUE ~ "other"
    ))
  cells <- easyNIS::nis_cell_counts(rows, by = "category") |>
    dplyr::arrange(category) |>
    dplyr::mutate(estimate = 10 * n)
  suppressed <- easyNIS::nis_suppress(cells, threshold = 1L,
    count_col = "n", hospital_col = "hospitals", weighted_cols = "estimate")
  stopifnot(identical(cells$category, c("companion", "other", "small")),
    identical(as.integer(cells$hospitals), c(2L, 2L, 1L)),
    identical(suppressed$n, c("Masked", "4", "\u22641")),
    identical(suppressed$estimate, c("Masked", "40", "\u22641")))
  write_evidence(list(cells = cells, suppressed = suppressed), file.path(evidence, "results.R"))
}

drivers <- list(open = drive_open, cohort = drive_cohort, survey = drive_survey,
  disclosure = drive_disclosure, study = drive_study, `study-ci` = drive_study_ci,
  `study-small` = drive_study_small, `study-reporting` = drive_study_reporting)
args <- commandArgs(trailingOnly = TRUE)
if (identical(args, "doctor")) {
  description <- read.dcf("DESCRIPTION", fields = c("Package", "Version"))
  stopifnot(description[1L, "Package"] == "easyNIS", getRversion() >= "4.1.0")
  print(verification_dependencies("."))
  cat("DOCTOR PASS easyNIS ", description[1L, "Version"], " / ", R.version.string, "\n",
    sep = "")
} else if (length(args) == 1L && args %in% names(drivers)) {
  verification_run(args, drivers[[args]],
    packages = study_verification_packages(args))
} else {
  stop(paste("Usage: Rscript --vanilla .agents/skills/verify/drive.R",
    paste(c("doctor", names(drivers)), collapse = "|")))
}
