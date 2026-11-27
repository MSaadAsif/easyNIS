#!/usr/bin/env Rscript

# Run each statistic in a fresh R process. Use an ignored scratch directory:
# Rscript --vanilla tools/benchmark-survey-summary.R prepare local/loop/survey-benchmark fixture
# Rscript --vanilla tools/benchmark-survey-summary.R default local/loop/survey-benchmark default
# Rscript --vanilla tools/benchmark-survey-summary.R mean local/loop/survey-benchmark mean
# Set EASYNIS_PROFILE=true for a separate run with elapsed-time profiling.
# The peak working set is cumulative and is reported on Windows.
library(easyNIS)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !args[[1L]] %in% c("prepare", "default", "mean")) {
  stop("Supply prepare, default, or mean, a scratch directory, and a run label.")
}
mode <- args[[1L]]
path <- args[[2L]]
label <- args[[3L]]

prepare_fixture <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  targets <- file.path(path, sprintf("NIS_%d.parquet", 2017:2021))
  if (any(file.exists(targets))) {
    stop("Choose a scratch directory without benchmark Parquet files.")
  }
  con <- DBI::dbConnect(duckdb::duckdb(), config = list(threads = 2L))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (year in 2017:2021) {
    target <- DBI::dbQuoteString(con, targets[[year - 2016L]])
    sql <- sprintf(
      "COPY (SELECT %d::INTEGER AS YEAR, i::INTEGER AS KEY_NIS,
         (1 + i %% 800)::INTEGER AS HOSP_NIS, (1 + i %% 20)::INTEGER AS NIS_STRATUM,
         4.5 + (h %% 100) * 0.01 AS DISCWT, (10 + h %% 85)::INTEGER AS AGE,
         (1 + (h >> 7) %% 6)::INTEGER AS RACE, (1 + (h >> 10) %% 6)::INTEGER AS PAY1,
         (1 + (h >> 14) %% 20)::INTEGER AS LOS,
         CASE WHEN i %% 31 = 1 THEN 'I501' ELSE 'Z000' END AS I10_DX1,
         CASE WHEN i %% 19 < 6 THEN '02703ZZ' ELSE '0XX0000' END AS I10_PR1
       FROM (SELECT i, hash(i, %d) AS h FROM range(150000) AS t(i)))
       TO %s (FORMAT PARQUET)",
      year,
      year,
      target
    )
    DBI::dbExecute(con, sql)
  }
}

measure <- function(phase, expr) {
  profile <- identical(Sys.getenv("EASYNIS_PROFILE"), "true")
  if (profile) {
    utils::Rprof(file.path(path, paste0(label, "-", phase, ".out")), event = "elapsed")
  }
  elapsed <- system.time({
    value <- force(expr)
  })[["elapsed"]]
  if (profile) {
    utils::Rprof(NULL)
  }
  peak <- if (.Platform$OS.type == "windows") {
    ps::ps_memory_info()[["peak_wset"]] / 1024^2
  } else {
    NA_real_
  }
  cat(sprintf("%s: %.3f s elapsed, %.1f MiB process peak working set\n", phase, elapsed, peak))
  value
}

run_benchmark <- function() {
  cat(R.version.string, R.version$platform, "\n")
  for (pkg in c("easyNIS", "duckdb", "gtsummary", "cardx", "survey")) {
    cat(pkg, as.character(utils::packageVersion(pkg)), "\n")
  }
  cat("Statistic:", mode, "\n")
  options(easyNIS.duckdb_config = list(threads = 2L, memory_limit = "512MB"))
  design <- measure("design", {
    nis <- nis_open(path, check_release = FALSE)
    con <- dbplyr::remote_con(nis)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    nis <- nis |>
      nis_flag_dx(heart_failure = "I50", position = "principal") |>
      nis_flag_pr(coronary = "02703")
    sql <- as.character(dbplyr::sql_render(dplyr::select(nis, YEAR, AGE, RACE, PAY1, LOS)))
    stopifnot(inherits(nis, "tbl_lazy"), grepl("read_parquet", sql, fixed = TRUE))
    cat(sql, "\n")
    nis_design(nis, heart_failure | coronary, keep = c(AGE, RACE, PAY1, LOS)) |>
      dplyr::filter(AGE >= 18)
  })
  cat("Domain rows:", nrow(design$variables), "\n")
  statistic <- if (mode == "mean") list(gtsummary::all_continuous() ~ "{mean} ({mean.std.error})")
  tbl <- measure(
    "table",
    gtsummary::tbl_svysummary(
      design,
      by = RACE,
      include = c(AGE, PAY1, LOS),
      type = list(c(AGE, LOS) ~ "continuous", PAY1 ~ "categorical"),
      statistic = statistic
    )
  )
  masked <- measure("suppression", nis_suppress(tbl))
  stopifnot(inherits(masked, "tbl_svysummary"))
  saveRDS(masked, file.path(path, paste0(label, "-masked.rds")))
}

if (mode == "prepare") {
  prepare_fixture(path)
} else {
  run_benchmark()
}
