# Developer benchmark on a fixed, entirely invented workload. Never supply licensed inputs.
# Rscript tools/benchmark-survey-preparation.R prepare <installed-library> <new-fixture-directory>
# Rscript tools/benchmark-survey-preparation.R run <installed-library> <fixture-directory> <new-output-directory>
main <- function(args) {
  if (!length(args) || !args[[1L]] %in% c("prepare", "run") ||
      length(args) != if (args[[1L]] == "prepare") 3L else 4L) {
    stop("Use prepare <library> <new-fixture-directory> or run <library> <fixture-directory> <new-output-directory>.")
  }
  .libPaths(c(normalizePath(args[[2L]], mustWork = TRUE), .libPaths()))
  library(easyNIS)
  if (normalizePath(find.package("easyNIS")) !=
      normalizePath(file.path(args[[2L]], "easyNIS"), mustWork = TRUE)) {
    stop("The benchmark must load the requested installed package.")
  }
  fixture <- args[[3L]]
  marker <- "easyNIS invented seven-million-row survey preparation v1"
  session <- nis_open()
  on.exit(nis_close(session), add = TRUE)
  DBI::dbExecute(session$connection, "SET memory_limit='2GB'")
  DBI::dbExecute(session$connection, "SET threads=4")
  if (args[[1L]] == "prepare") {
    if (file.exists(fixture)) stop("Fixture destination must not already exist.")
    if (!dir.create(fixture, recursive = TRUE)) stop("Could not create fixture directory.")
    for (part in 0:3) {
      first <- sprintf("%.0f", part * 1750000)
      last <- sprintf("%.0f", (part + 1) * 1750000)
      DBI::dbExecute(session$connection, paste0(
        "COPY (SELECT 2022::INTEGER AS YEAR, (i+1)::BIGINT AS KEY_NIS, ",
        "lpad(CAST(1+i%4096 AS VARCHAR),5,'0') AS HOSP_NIS, ",
        "lpad(CAST(1+floor((i%4096)/32)::INTEGER AS VARCHAR),3,'0') AS NIS_STRATUM, ",
        "(2+i%5)::DOUBLE AS DISCWT, (i%90)::DOUBLE AS AGE FROM range(",
        first, "::BIGINT,", last, "::BIGINT) t(i)) TO ",
        DBI::dbQuoteString(session$connection, file.path(fixture, paste0("part-", part + 1L, ".parquet"))),
        " (FORMAT PARQUET)"))
    }
    writeLines(marker, file.path(fixture, "INVENTED.txt"))
    return(invisible(NULL))
  }
  marker_path <- file.path(fixture, "INVENTED.txt")
  if (!file.exists(marker_path) || !identical(readLines(marker_path), marker)) {
    stop("Use only the fixture produced by prepare.")
  }
  output <- args[[4L]]
  if (file.exists(output)) stop("Output destination must not already exist.")
  if (!dir.create(output, recursive = TRUE)) stop("Could not create output directory.")
  paths <- file.path(fixture, paste0("part-", 1:4, ".parquet"))
  before <- file.info(paths)[, c("size", "mtime")]
  stages <- list()
  timed <- function(name, expression) {
    started <- proc.time()[["elapsed"]]
    value <- force(expression)
    stages[[name]] <<- proc.time()[["elapsed"]] - started
    value
  }
  data <- timed("import", nis_import(session, paths, 2022))
  reference <- timed("reference", DBI::dbGetQuery(session$connection, paste0(
    "SELECT COUNT(*) AS n, SUM(DISCWT) AS weights, COUNT(DISTINCT HOSP_NIS) AS hospitals, ",
    "COUNT(DISTINCT NIS_STRATUM) AS strata FROM ", DBI::dbQuoteIdentifier(session$connection, data$view))))
  stopifnot(reference$n == 7000000, reference$weights == 28000000,
    reference$hospitals == 4096, reference$strata == 128)
  design <- timed("native_design", nis_survey_design(data, "AGE", TRUE, "hospital_wr", "fail"))
  stopifnot(design$population$discharges == reference$n,
    design$population$hospitals == reference$hospitals, design$population$strata == reference$strata,
    design$population$degrees_of_freedom == reference$hospitals - reference$strata,
    sum(stats::weights(design$design)) == reference$weights,
    identical(names(design$design$variables), c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "AGE")),
    identical(before, file.info(paths)[, c("size", "mtime")]), !design$provenance$analysis_ready)
  write.csv(data.frame(stage = names(stages), elapsed_seconds = unlist(stages)),
    file.path(output, "times.csv"), row.names = FALSE)
  writeLines(deparse(body(nis_survey_design)), file.path(output, "constructor.txt"))
  capture.output(sessionInfo(), file = file.path(output, "session.txt"))
  writeLines("SUCCESS: invented accounting matched; no licensed support or memory envelope established.",
    file.path(output, "success.txt"))
}

if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
