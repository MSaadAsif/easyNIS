#!/usr/bin/env Rscript

# Run prepare, early, and late in separate R processes against the same file.
# On Windows, PeakPagedMemorySize64 is the OS process peak commit counter.
library(easyNIS)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[[1L]] %in% c("prepare", "early", "late")) {
  stop("Supply prepare, early, or late and a scratch directory.")
}
mode <- args[[1L]]
path <- args[[2L]]

if (mode == "prepare") {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  target <- file.path(path, "NIS_2019.parquet")
  if (file.exists(target)) {
    stop("Choose a scratch directory without NIS_2019.parquet.")
  }
  source <- nis_open(nis_example(years = 2019))
  con <- dbplyr::remote_con(source)
  extras <- paste0("CAST(replica + ", seq_len(80L), " AS INTEGER) AS extra_", seq_len(80L))
  fields <- paste(c("discharges.*", extras), collapse = ", ")
  dest <- DBI::dbQuoteString(con, file.path(normalizePath(path, winslash = "/"), basename(target)))
  DBI::dbExecute(
    con,
    paste0(
      "COPY (SELECT ",
      fields,
      " FROM (",
      dbplyr::sql_render(source),
      ") AS discharges CROSS JOIN range(5000) AS copies(replica)) TO ",
      dest,
      " (FORMAT PARQUET)"
    )
  )
  DBI::dbDisconnect(con, shutdown = TRUE)
  quit()
}

if (.Platform$OS.type != "windows") {
  stop("Peak commit measurement requires Windows.")
}
options(easyNIS.duckdb_config = list(threads = 1L))
source <- nis_open(path, check_release = FALSE)
project <- function(data) dplyr::select(data, nis_vars_design(), AGE, LOS)
if (mode == "early") {
  projected <- project(source)
  cat(as.character(dbplyr::sql_render(projected)), "\n")
  result <- dplyr::collect(projected)
} else {
  wide <- dplyr::collect(source)
  result <- project(wide)
}
peak_bytes <- system2(
  "powershell.exe",
  c(
    "-NoProfile",
    "-Command",
    shQuote(sprintf("(Get-Process -Id %d).PeakPagedMemorySize64", Sys.getpid()), type = "cmd")
  ),
  stdout = TRUE
)
stopifnot(length(peak_bytes) == 1L, is.finite(as.double(peak_bytes)))
cat(R.version.string, R.version$platform, "DuckDB", as.character(utils::packageVersion("duckdb")), "\n")
cat(
  mode,
  "rows",
  nrow(result),
  "source columns",
  length(colnames(source)),
  "selected columns",
  ncol(result),
  "LOS sum",
  sum(result$LOS),
  "peak commit MiB",
  round(as.double(peak_bytes) / 1024^2, 1),
  "\n"
)
DBI::dbDisconnect(dbplyr::remote_con(source), shutdown = TRUE)
