find_main_repo <- function(start = ".") {
  start <- normalizePath(start, mustWork = TRUE)
  common_dir <- tryCatch(suppressWarnings(system2("git",
    c("-C", start, "rev-parse", "--git-common-dir"), stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  status <- attr(common_dir, "status")
  if (!length(common_dir) || (length(status) && status != 0L)) {
    return(normalizePath(start, mustWork = TRUE))
  }
  common_path <- common_dir[[1L]]
  is_absolute <- grepl("^[A-Za-z]:[/\\\\]", common_path) ||
    startsWith(common_path, "/") || startsWith(common_path, "\\\\")
  if (!is_absolute) {
    common_path <- file.path(start, common_path)
  }
  dirname(normalizePath(common_path, mustWork = TRUE))
}

read_main_renviron <- function(start = ".") {
  path <- file.path(find_main_repo(start), ".Renviron")
  if (file.exists(path)) {
    shell_environment <- Sys.getenv()
    shell_environment <- shell_environment[nzchar(shell_environment)]
    readRenviron(path)
    if (length(shell_environment)) do.call(Sys.setenv, as.list(shell_environment))
  }
  invisible(path)
}

path_is_within <- function(path, parent) {
  path <- tolower(sub("/$", "", normalizePath(path, winslash = "/", mustWork = FALSE)))
  parent <- tolower(sub("/$", "", normalizePath(parent, winslash = "/", mustWork = FALSE)))
  identical(path, parent) || startsWith(path, paste0(parent, "/"))
}

resolve_loop_dir <- function(main_repo, requested = Sys.getenv("EASYNIS_LOOP_DIR", unset = "")) {
  main_repo <- normalizePath(main_repo, winslash = "/", mustWork = TRUE)
  expected_root <- file.path(main_repo, "local", "loop")
  if (!dir.exists(expected_root)) dir.create(expected_root, recursive = TRUE)
  expected_root <- normalizePath(expected_root, winslash = "/", mustWork = TRUE)
  if (!nzchar(requested)) requested <- expected_root
  if (!grepl("^(?:[A-Za-z]:[/\\\\]|/|\\\\\\\\)", requested)) {
    requested <- file.path(main_repo, requested)
  }
  candidate <- normalizePath(requested, winslash = "/", mustWork = FALSE)
  if (!path_is_within(candidate, expected_root)) {
    stop("EASYNIS_LOOP_DIR must resolve inside the main checkout's ignored local loop directory.",
      call. = FALSE)
  }
  if (!dir.exists(candidate) && !dir.create(candidate, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create the local loop output directory.", call. = FALSE)
  }
  candidate <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  if (!path_is_within(candidate, expected_root)) {
    stop("EASYNIS_LOOP_DIR must resolve inside the main checkout's ignored local loop directory.",
      call. = FALSE)
  }
  relative <- substring(candidate, nchar(main_repo) + 2L)
  ignored <- suppressWarnings(system2("git", c("-C", main_repo, "check-ignore", "--quiet", "--",
    relative), stdout = FALSE, stderr = FALSE))
  if (!identical(ignored, 0L)) {
    stop("The local loop output directory must be ignored by Git.", call. = FALSE)
  }
  candidate
}

redact_paths <- function(text) {
  text <- as.character(text)
  text <- gsub("(?i)\\b[A-Z]:[/\\\\][^\\r\\n]*", "[local path]", text, perl = TRUE)
  text <- gsub("(?<!:)//[^\\r\\n]*", "[local path]", text, perl = TRUE)
  text <- gsub("(?i)\\\\\\\\[^\\r\\n]*", "[local path]", text, perl = TRUE)
  gsub("(?<![A-Za-z0-9_:/])/(?!/)[^\\r\\n]*", "[local path]", text, perl = TRUE)
}

redact_public_text <- function(text) {
  number <- "[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?"
  gsub(number, "[number]", redact_paths(text), perl = TRUE)
}

redact_public_diagnostic <- function(text) {
  text <- as.character(text)
  contains_number <- grepl("[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?[iL]?",
    text, perl = TRUE)
  text[contains_number] <- "[diagnostic text redacted]"
  redact_public_text(text)
}

safe_static_condition_messages <- c(
  "The requested operation completed with a warning."
)

safe_condition_record <- function(condition, calling_function) {
  message <- conditionMessage(condition)
  public_message <- if (message %in% safe_static_condition_messages) {
    message
  } else {
    "<redacted: unrecognized message>"
  }
  list(
    condition_class = class(condition)[[1L]],
    calling_function = calling_function,
    message = public_message
  )
}

git_evidence <- function() {
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"),
    stdout = TRUE, stderr = FALSE), error = function(e) character())
  status <- tryCatch(system2("git", c("status", "--porcelain", "--untracked-files=all"),
    stdout = TRUE, stderr = FALSE), error = function(e) "dirty")
  commit_status <- attr(commit, "status", exact = TRUE)
  status_status <- attr(status, "status", exact = TRUE)
  list(
    commit = if (length(commit) && (!length(commit_status) || commit_status == 0L)) commit[[1L]] else NA_character_,
    working_tree_clean = !length(status) && (!length(status_status) || status_status == 0L)
  )
}

valid_receipt_time <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) return(FALSE)
  parsed <- suppressWarnings(as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  length(parsed) == 1L && !is.na(parsed)
}

numeric_reference_value <- function(value) {
  parsed <- suppressWarnings(as.numeric(value))
  if (length(parsed) != 1L || !is.finite(parsed)) return(NA_real_)
  parsed
}

valid_named_fields <- function(value, required) {
  is.list(value) && all(required %in% names(value))
}

valid_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && nzchar(value)
}

valid_estimate_interval <- function(value) {
  if (!is.character(value)) return(FALSE)
  interval <- vapply(value, numeric_reference_value, numeric(1))
  length(interval) == 2L && all(is.finite(interval)) && interval[[1L]] <= interval[[2L]]
}

valid_reference_estimate <- function(estimate) {
  required <- c("id", "label", "estimate_printed", "estimate", "ci_printed", "ci")
  if (!valid_named_fields(estimate, required)) return(FALSE)
  valid_estimate_text_fields(estimate) &&
    is.finite(numeric_reference_value(estimate$estimate)) &&
    valid_estimate_interval(estimate$ci)
}

valid_reference_study_fields <- function(study) {
  valid_nonempty_string(study$id) && valid_reference_doi(study$doi) &&
    valid_nonempty_string(study$cohort_definition) && valid_reference_tolerance(study$tolerance)
}

valid_reference_doi <- function(value) {
  valid_nonempty_string(value) && grepl("^10[.][0-9]{4,9}/[^[:space:]]+$", value)
}

valid_reference_tolerance <- function(value) {
  is.numeric(value) && length(value) == 1L && is.finite(value) && value >= 0
}

valid_estimate_text_fields <- function(estimate) {
  valid_nonempty_string(estimate$id) && valid_nonempty_string(estimate$label) &&
    valid_estimate_printed_text(estimate$estimate_printed) &&
    valid_estimate_printed_text(estimate$ci_printed)
}

valid_estimate_printed_text <- function(value) {
  is.character(value) && nzchar(value)
}

valid_reference_estimates <- function(estimates) {
  is.list(estimates) && length(estimates) > 0L &&
    all(vapply(estimates, valid_reference_estimate, logical(1))) &&
    !anyDuplicated(vapply(estimates, `[[`, character(1), "id"))
}

valid_reference_study <- function(study) {
  required <- c("id", "doi", "cohort_definition", "tolerance", "headline_estimates")
  valid_named_fields(study, required) && valid_reference_study_fields(study) &&
    valid_reference_estimates(study$headline_estimates)
}

valid_reference_studies <- function(studies) {
  if (!is.list(studies) || length(studies) != 3L) return(FALSE)
  if (!all(vapply(studies, valid_reference_study, logical(1)))) return(FALSE)
  ids <- vapply(studies, `[[`, character(1), "id")
  !anyDuplicated(ids)
}

load_reference_studies <- function(path) {
  if (!requireNamespace("yaml", quietly = TRUE) || !file.exists(path)) return(NULL)
  reference <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (!is.list(reference) || is.null(reference$studies)) return(NULL)
  reference$studies
}

valid_receipt_results <- function(results, reference_study) {
  if (!is.list(results) || length(results) != length(reference_study$headline_estimates)) return(FALSE)
  expected <- stats::setNames(reference_study$headline_estimates,
    vapply(reference_study$headline_estimates, `[[`, character(1), "id"))
  receipt_ids <- vapply(results, receipt_result_id, character(1))
  if (!valid_receipt_id_set(receipt_ids, names(expected))) return(FALSE)
  all(vapply(results, valid_receipt_result, logical(1), expected = expected,
    reference_study = reference_study))
}

receipt_result_id <- function(result) {
  if (is.list(result) && is.character(result$estimate_id) && length(result$estimate_id) == 1L) {
    result$estimate_id
  } else {
    ""
  }
}

valid_receipt_id_set <- function(receipt_ids, expected_ids) {
  !any(!nzchar(receipt_ids)) && !anyDuplicated(receipt_ids) &&
    setequal(receipt_ids, expected_ids)
}

valid_receipt_result <- function(result, expected, reference_study) {
  required <- c("estimate_id", "computed_estimate", "reference_value", "reference_ci",
    "tolerance", "comparison_result")
  if (!valid_receipt_result_fields(result, required)) return(FALSE)
  reference <- expected[[result$estimate_id]]
  if (is.null(reference)) return(FALSE)
  computed <- numeric_reference_value(result$computed_estimate)
  reference_value <- numeric_reference_value(reference$estimate)
  tolerance <- numeric_reference_value(reference_study$tolerance)
  comparison <- if (is.finite(computed) && abs(computed - reference_value) <= tolerance) "pass" else "fail"
  is.finite(computed) && valid_receipt_reference_values(result, reference, reference_value, tolerance) &&
    valid_receipt_comparison(result, comparison)
}

valid_receipt_result_fields <- function(result, required) {
  is.list(result) && all(required %in% names(result)) && valid_receipt_result_id(result)
}

valid_receipt_result_id <- function(result) {
  is.character(result$estimate_id) && length(result$estimate_id) == 1L &&
    !is.na(result$estimate_id) && nzchar(result$estimate_id)
}

valid_receipt_comparison <- function(result, comparison) {
  identical(result$comparison_result, comparison) && identical(comparison, "pass")
}

valid_receipt_reference_values <- function(result, reference, value, tolerance) {
  identical(numeric_reference_value(result$reference_value), value) &&
    identical(as.numeric(unlist(result$reference_ci)), as.numeric(vapply(reference$ci,
      numeric_reference_value, numeric(1)))) &&
    identical(numeric_reference_value(result$tolerance), tolerance)
}

valid_study_receipt <- function(receipt, current_commit, reference_study) {
  is.list(receipt) && identical(receipt$package_commit_hash, current_commit) &&
    identical(receipt$study_id, reference_study$id) &&
    valid_receipt_time(receipt$verified_at) &&
    valid_receipt_results(receipt$results, reference_study)
}

study_verification_ready <- function(path, current_commit, reference_study) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE) ||
      !valid_reference_study(reference_study)) return(FALSE)
  receipt <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL)
  valid_study_receipt(receipt, current_commit, reference_study)
}

parse_open_issue_query <- function(output, status = 0L) {
  if (length(status) && status != 0L || !length(output)) {
    return(list(ok = FALSE, count = NA_integer_))
  }
  issues <- tryCatch(jsonlite::fromJSON(paste(output, collapse = "\n"),
    simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(issues)) return(list(ok = FALSE, count = NA_integer_))
  list(ok = TRUE, count = length(issues))
}

check_result_counts <- function(value) {
  count <- function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0) return(as.integer(x))
    length(x)
  }
  c(errors = count(value$errors), warnings = count(value$warnings), notes = count(value$notes))
}

quality_evidence_valid <- function(item, current_commit, current_tree_clean) {
  is.list(item) && isTRUE(current_tree_clean) &&
    identical(item$commit, current_commit) && identical(item$working_tree_clean, TRUE)
}

private_quality_diagnostics <- function(checks, records) {
  tool_names <- intersect(c("goodpractice", "pkgcheck"), names(checks))
  failed <- tool_names[vapply(tool_names, function(name) {
    matching_records <- Filter(function(record) identical(record$step, name), records)
    length(matching_records) > 0L && any(vapply(matching_records, function(record) {
      identical(record$pass, FALSE)
    }, logical(1)))
  }, logical(1))]
  stats::setNames(lapply(failed, function(name) {
    warnings <- checks[[name]]$warning_conditions
    if (is.null(warnings)) warnings <- list()
    list(result = checks[[name]]$value,
      warnings = warnings)
  }), failed)
}

capture_quality_step <- function(name, fn) {
  started <- proc.time()[["elapsed"]]
  warnings <- list()
  value <- tryCatch(withCallingHandlers(fn(),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }), error = identity)
  list(name = name, pass = !inherits(value, "error"),
    error_class = if (inherits(value, "error")) class(value)[[1L]] else "",
    error = if (inherits(value, "error")) "diagnostic text redacted" else "",
    warning_conditions = warnings,
    warnings = if (length(warnings)) "warning(s) captured" else "",
    elapsed_seconds = unname(proc.time()[["elapsed"]] - started), value = value)
}

goodpractice_prep_failed <- function(prep_values) {
  any(vapply(prep_values, inherits, logical(1), "try-error"))
}

goodpractice_check_status <- function(checks) {
  statuses <- lapply(checks, function(check) {
    if (is.list(check) && "status" %in% names(check)) check$status else check
  })
  if (any(vapply(statuses, function(status) identical(status, FALSE), logical(1)))) return(FALSE)
  if (any(vapply(statuses, function(status) length(status) != 1L || is.na(status), logical(1)))) {
    return(NA)
  }
  TRUE
}

goodpractice_pass <- function(value) {
  if (!inherits(value, "goodPractice") || !is.list(value$checks) || !length(value$checks)) {
    return(NA)
  }
  prep_values <- value[setdiff(names(value), "checks")]
  if (goodpractice_prep_failed(prep_values)) return(FALSE)
  status <- goodpractice_check_status(value$checks)
  if (!isTRUE(status)) return(status)
  failed <- tryCatch(goodpractice::failed_checks(value), error = function(e) NULL)
  if (is.null(failed)) return(NA)
  !length(failed)
}

quality_public_detail <- function(name, passed) {
  if (name %in% c("goodpractice", "pkgcheck") && identical(passed, FALSE)) {
    return("check failures present")
  }
  ""
}

quality_public_diagnostic_counts <- function(value, warning_conditions = list()) {
  goodpractice_result <- if (inherits(value, "pkgcheck")) {
    value$goodpractice
  } else if (inherits(value, "goodPractice")) {
    value
  } else {
    NULL
  }
  checks <- goodpractice_result$checks
  failed_checks <- if (is.list(checks)) {
    sum(vapply(checks, function(check) {
      is.list(check) && identical(check$status, FALSE)
    }, logical(1)))
  } else {
    0L
  }
  rcmdcheck <- goodpractice_result$rcmdcheck
  rcmdcheck_errors <- if (inherits(rcmdcheck, "try-error")) {
    1L
  } else if (is.list(rcmdcheck)) {
    length(rcmdcheck$errors)
  } else {
    0L
  }
  list(failed_checks = as.integer(failed_checks),
    rcmdcheck_errors = as.integer(rcmdcheck_errors),
    captured_warnings = as.integer(length(warning_conditions)))
}

quality_receipt_record <- function(x, evidence, status, passed, detail) {
  diagnostic_counts <- quality_public_diagnostic_counts(x$value, x$warning_conditions)
  c(list(step = x$name, status = status, pass = passed,
    error_class = x$error_class, result_class = paste(class(x$value), collapse = ","),
    commit = evidence$commit, working_tree_clean = evidence$working_tree_clean,
    detail = detail, warnings = x$warnings, elapsed_seconds = x$elapsed_seconds),
    diagnostic_counts)
}

write_private_quality_diagnostics <- function(run_dir, checks, records) {
  diagnostics <- private_quality_diagnostics(checks, records)
  if (!length(diagnostics)) return(NULL)
  private_dir <- file.path(run_dir, "private")
  tryCatch({
    if (!dir.exists(private_dir) && !suppressWarnings(dir.create(private_dir, recursive = TRUE))) {
      stop("directory creation failed", call. = FALSE)
    }
    output <- file.path(private_dir, "quality-diagnostics.rds")
    saveRDS(diagnostics, output)
    output
  }, error = function(error) {
    warning("Could not save private quality diagnostics (", class(error)[[1L]], ").",
      call. = FALSE)
    NULL
  })
}

coverage_percent_value <- function(item) {
  value <- item$value
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) return(NA_real_)
  as.numeric(value)
}

private_sanity_summary <- function(step, result) {
  if (identical(step, "weighted_descriptives")) {
    if (!is.data.frame(result)) return(NULL)
    return(result[vapply(result, is.numeric, logical(1))])
  }
  if (identical(step, "regression")) return(summary(result)$coefficients)
  NULL
}

exported_example_status <- function(root = ".") {
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\(([^)]+)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  has_examples <- vapply(exports, function(name) {
    file <- file.path(root, "man", paste0(name, ".Rd"))
    if (!file.exists(file)) return(FALSE)
    lines <- readLines(file, warn = FALSE)
    example_start <- grep("^\\\\examples\\s*\\{", lines, perl = TRUE)
    if (!length(example_start)) return(FALSE)
    block <- paste(lines[example_start[[1L]]:length(lines)], collapse = "\n")
    !grepl("^\\\\examples\\s*\\{\\s*\\\\dontrun\\s*\\{", block, perl = TRUE)
  }, logical(1))
  list(exports = exports, has_examples = has_examples)
}
