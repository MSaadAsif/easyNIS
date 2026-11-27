pkgcheck_positions_allowed <- function(check, positions) {
  # Keep these exact file/function pairs in sync with the roadmap.
  exceptions <- switch(
    check,
    complexity_function_length = c(
      "R/convert-encoding.R:nis_convert_sas_encoding",
      "R/example.R:.nis_example_base_records",
      "R/lazy-survey-stat.R:nis_survey_aggregate"
    ),
    complexity_unused_internal = c(
      "R/code-layout.R:nis_diagnosis_fields",
      "R/lazy-survey.R:`$.nis_survey`",
      "R/open-discovery.R:nis_open_available_years",
      "R/study-cache.R:nis_study_cache_key",
      "R/study-disclosure.R:nis_study_report_support",
      "R/study-disclosure.R:nis_study_fit_report_model",
      "R/study-disclosure.R:nis_study_render_table",
      "R/study-disclosure.R:nis_study_summary_table",
      "R/study-disclosure.R:nis_study_trend_table",
      "R/study-disclosure.R:nis_study_model_table",
      "R/study-disclosure.R:nis_study_flow",
      "R/study-reporting.R:nis_study_trend_estimates",
      "R/study-reporting.R:nis_study_checklist",
      "R/study-reporting.R:nis_study_reporting",
      "R/study-reporting.R:nis_study_methods"
    ),
    character()
  )
  length(positions) > 0L &&
    all(vapply(
      positions,
      function(position) {
        if (!valid_nonempty_string(position$filename) || !valid_nonempty_string(position$line)) {
          return(FALSE)
        }
        name <- sub(" \\([0-9]+ lines\\)$", "", position$line)
        paste(position$filename, name, sep = ":") %in% exceptions
      },
      logical(1)
    ))
}

pkgcheck_pass <- function(value) {
  if (!inherits(value, "pkgcheck")) {
    return(NA)
  }
  gp <- value$goodpractice
  if (!inherits(gp, "goodPractice") || !length(gp$checks)) {
    return(NA)
  }
  if (goodpractice_prep_failed(gp[setdiff(names(gp), "checks")])) {
    return(FALSE)
  }
  failures <- goodpractice::failed_checks(gp)
  allowed <- vapply(
    failures,
    function(check) pkgcheck_positions_allowed(check, gp$checks[[check]]$positions),
    logical(1)
  )
  if (!all(allowed)) {
    return(FALSE)
  }
  if (!all(c("complexity_function_length", "complexity_unused_internal") %in% names(gp$checks))) {
    return(NA)
  }
  # Use pkgcheck's own required-check summary. There is no exported verdict.
  report <- tryCatch(pkgcheck:::summarise_all_checks(value), error = function(error) NULL)
  result <- attr(report, "checks_okay", exact = TRUE)
  if (is.logical(result) && length(result) == 1L) result else NA
}
check_counts_for <- function(value) {
  has_counts <- is.list(value) && all(c("errors", "warnings", "notes") %in% names(value))
  if (inherits(value, "rcmdcheck") || has_counts) {
    return(check_result_counts(value))
  }
  NULL
}
quality_step_pass <- function(x, definition, counts) {
  value <- x$value
  if (identical(value, "skipped_by_selection") || identical(value, "not installed")) {
    return(NA)
  }
  if (inherits(value, "error")) {
    return(FALSE)
  }
  if (!is.null(definition$pass)) {
    return(definition$pass(x))
  }
  if (!is.null(counts)) {
    return(x$pass && all(counts == 0L))
  }
  isTRUE(x$pass)
}
quality_step_status <- function(value, passed) {
  if (identical(value, "skipped_by_selection")) {
    return("skipped_by_selection")
  }
  if (identical(value, "not installed")) {
    return("skipped_not_installed")
  }
  if (inherits(value, "error")) {
    return("failed")
  }
  if (is.na(passed)) {
    return("not_verified")
  }
  "completed"
}
quality_step_detail <- function(x, definition, counts, passed) {
  if (inherits(x$value, "error")) {
    return(x$error)
  }
  if (!is.null(definition$detail)) {
    return(definition$detail(x, passed))
  }
  if (!is.null(counts)) {
    return(paste(names(counts), counts, collapse = " | "))
  }
  ""
}

quality_record <- function(x, evidence) {
  value <- x$value
  counts <- check_counts_for(value)
  definition <- quality_definition(x$name)
  passed <- quality_step_pass(x, definition, counts)
  detail <- redact_paths(quality_step_detail(x, definition, counts, passed))
  quality_receipt_record(x, evidence, quality_step_status(value, passed), passed, detail)
}
