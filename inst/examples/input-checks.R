# Offline walkthrough: source(system.file("examples/input-checks.R", package = "easyNIS"))$value
# All records are invented. The returned summary is not a diagnostic exporter.
library(easyNIS)
(function() {
  session <- nis_open()
  paths <- character()
  on.exit({ nis_close(session); unlink(paths) }, add = TRUE)
  core <- nis_synthetic_data(2022)$core
  cases <- list(canonical = core, legacy_aliases = core, wrong_year = core)
  names(cases$legacy_aliases)[match(c("HOSP_NIS", "DISCWT"), names(core))] <-
    c("HOSPID", "TRENDWT")
  cases$wrong_year$YEAR[1L] <- 2021L
  declarations <- list(conversion = "invented example", revision = "invented-1",
    prefiltered = FALSE, labels = "invented", missing_reasons = "not audited")
  rows <- lapply(names(cases), function(case) {
    path <- tempfile(fileext = ".parquet")
    paths <<- c(paths, path)
    DBI::dbWriteTable(session$connection, "invented_input", cases[[case]], overwrite = TRUE)
    DBI::dbExecute(session$connection, paste0("COPY invented_input TO ",
      DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
    imported <- tryCatch(nis_import(session, path, 2022, provenance = declarations),
      nis_structure_error = identity)
    if (inherits(imported, "nis_structure_error")) {
      stopifnot(case == "wrong_year", identical(imported$check, "invalid_year"),
        imported$affected == 1, identical(imported$component, "core"),
        identical(imported$fields, "YEAR"))
      # No validation report exists for a rejected import.
      return(data.frame(case = case, import = "rejected", structural_errors = NA,
        analysis_ready = NA, check = imported$check))
    }
    report <- nis_validate(imported, fields = c("HOSP_NIS", "DISCWT", "LOS"))
    stopifnot(identical(report$analysis_ready, FALSE),
      all(c("annual_layout_unverified", "conversion_unverified") %in% report$issues$check),
      all(report$components$state[report$components$component != "core"] == "not_supplied"))
    if (case == "legacy_aliases") {
      absent <- report$issues$field[report$issues$check == "required_field_absent"]
      stopifnot(report$structural_errors, setequal(absent, c("HOSP_NIS", "DISCWT")),
        all(report$fields$state[1:2] == "unverified_absent"),
        all(is.na(report$fields$record_nulls[1:2])))
    } else {
      stopifnot(!report$structural_errors, all(report$fields$state == "present"))
      selected <- nis_select(imported, c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT"))
      omitted <- nis_validate(selected, fields = "LOS")$fields
      stopifnot(identical(omitted$state, "user_omitted"), is.na(omitted$record_nulls))
    }
    data.frame(case = case, import = "accepted", structural_errors = report$structural_errors,
      analysis_ready = report$analysis_ready,
      check = if (case == "legacy_aliases") "required_field_absent" else "metadata_unverified")
  })
  do.call(rbind, rows)
})()
