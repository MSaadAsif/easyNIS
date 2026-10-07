args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !dir.exists(args[1L])) {
  stop("Usage: Rscript tools/validate-local-parquet.R <input-directory> <private-output-directory>")
}
if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("This developer tool requires pkgload and must run from the easyNIS checkout.")
}
pkgload::load_all(quiet = TRUE)
dir.create(args[2L], recursive = TRUE, showWarnings = FALSE)
expected_counts <- c(`2017` = 7159694, `2018` = 7105498, `2019` = 7083805,
                     `2020` = 6471165, `2021` = 6666752, `2022` = 6578372)
summary <- lapply(2017:2022, function(year) {
  path <- file.path(args[1L], paste0("NIS_", year, ".parquet"))
  if (!dir.exists(path)) stop("Missing annual directory for ", year)
  session <- nis_open()
  on.exit(nis_close(session), add = TRUE)
  started <- proc.time()[["elapsed"]]
  imported <- tryCatch(nis_import(session, path, year), error = function(error) error)
  if (inherits(imported, "error")) {
    failure <- conditionMessage(imported)
    writeLines(failure, file.path(args[2L], paste0("import-failure-", year, ".txt")))
    return(data.frame(
      year = year, actual_rows = NA_real_, official_core_rows = expected_counts[as.character(year)],
      row_count_matches = NA, structural_errors = TRUE, analysis_ready = FALSE,
      seconds = proc.time()[["elapsed"]] - started, scope = "import_rejected",
      failure = failure, stringsAsFactors = FALSE, row.names = NULL
    ))
  }
  data <- imported
  report <- nis_validate(data)
  utils::write.csv(report$issues, file.path(args[2L], paste0("issues-", year, ".csv")),
                   row.names = FALSE)
  rows <- as.numeric(DBI::dbGetQuery(session$connection, paste0(
    "SELECT COUNT(*) AS n FROM ", DBI::dbQuoteIdentifier(session$connection, data$view)
  ))$n)
  data.frame(
    year = year, actual_rows = rows, official_core_rows = expected_counts[as.character(year)],
    row_count_matches = rows == expected_counts[as.character(year)],
    structural_errors = report$structural_errors, analysis_ready = report$analysis_ready,
    seconds = proc.time()[["elapsed"]] - started, scope = report$scope, failure = NA_character_,
    stringsAsFactors = FALSE, row.names = NULL
  )
})
utils::write.csv(do.call(rbind, summary), file.path(args[2L], "summary.csv"), row.names = FALSE)
writeLines(c(
  "# Private structural import checks", "",
  "Source counts: https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp",
  "2019 and 2020 reference counts refer to the documented V2 releases.",
  "Count equality does not identify the conversion or release revision.",
  "All checks use aggregate SQL results. No discharge records are exported.",
  "Merged component fields and derived scores have not been authenticated.",
  "No survey, model, clinical cohort, or disclosure validation is claimed.",
  paste("R version:", getRversion()),
  paste("DuckDB R package:", utils::packageVersion("duckdb")),
  paste("Created at:", format(Sys.time(), tz = "UTC", usetz = TRUE))
), file.path(args[2L], "README.md"))
cat("Finished structural checks for six annual inputs. Receipts saved privately.\n")
