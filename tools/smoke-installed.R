args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !dir.exists(args)) stop("Supply the isolated installed-package library.")
.libPaths(c(normalizePath(args), .libPaths()))
library(easyNIS)
if (normalizePath(find.package("easyNIS")) != normalizePath(file.path(args, "easyNIS"))) {
  stop("The workflow must use the newly installed source package.")
}
exercise_year <- function(year) {
  fixture <- nis_synthetic_data(year)
  core <- fixture$core
  core$I10_DX1 <- rep(c("A001", "B002"), length.out = nrow(core))
  session <- nis_open()
  path <- tempfile(fileext = ".parquet")
  on.exit({ nis_close(session); unlink(path) }, add = TRUE)
  DBI::dbWriteTable(session$connection, "invented", core)
  DBI::dbExecute(session$connection, paste0("COPY invented TO ",
    DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
  data <- nis_import(session, path, year)
  report <- nis_validate(data)
  stopifnot(!report$structural_errors, identical(report$analysis_ready, FALSE))
  codes <- nis_code_set("A001", "ICD10CM", year, "invented-smoke-1", "invented fixture", "verification")
  flagged <- nis_flag_codes(data, "invented_flag", codes, "principal_diagnosis", "no_match")
  rows <- nis_collect(flagged, c("KEY_NIS", "invented_flag"))
  expected <- core$I10_DX1[match(rows$KEY_NIS, core$KEY_NIS)] == "A001"
  stopifnot(nrow(rows) == nrow(core), identical(rows$invented_flag, expected))
  cat("Invented year", year, "passed import, validation, flags, row preservation and R comparison.\n")
}
for (year in 2017:2022) exercise_year(year)
stopifnot(nrow(nis_supported_years(supported_only = TRUE)) == 0L)
cat("Installed workflow passed; year support remains experimental.\n")
