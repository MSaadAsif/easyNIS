valid_receipt_time <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) return(FALSE)
  parsed <- suppressWarnings(as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  length(parsed) == 1L && !is.na(parsed)
}

numeric_reference_value <- function(value) {
  if ((!is.numeric(value) && !is.character(value)) || length(value) != 1L) return(NA_real_)
  parsed <- suppressWarnings(as.numeric(value))
  if (length(parsed) != 1L || !is.finite(parsed)) return(NA_real_)
  parsed
}

valid_named_fields <- function(value, required) {
  is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) &&
    all(required %in% names(value))
}

valid_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
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
    valid_nonempty_string(estimate$estimate_printed) &&
    valid_nonempty_string(estimate$ci_printed)
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
  valid_named_fields(result, required) && valid_receipt_result_id(result)
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
    (is.list(result$reference_ci) || is.numeric(result$reference_ci) || is.character(result$reference_ci)) &&
    identical(vapply(result$reference_ci, numeric_reference_value, numeric(1)), as.numeric(vapply(reference$ci,
      numeric_reference_value, numeric(1)))) &&
    identical(numeric_reference_value(result$tolerance), tolerance)
}

valid_study_receipt <- function(receipt, current_commit, reference_study) {
  required <- c("package_commit_hash", "study_id", "verified_at", "results")
  valid_named_fields(receipt, required) &&
    identical(receipt[["package_commit_hash", exact = TRUE]], current_commit) &&
    identical(receipt[["study_id", exact = TRUE]], reference_study$id) &&
    valid_receipt_time(receipt[["verified_at", exact = TRUE]]) &&
    valid_receipt_results(receipt[["results", exact = TRUE]], reference_study)
}

study_verification_ready <- function(path, current_commit, reference_study) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE) ||
      !valid_reference_study(reference_study)) return(FALSE)
  receipt_bytes <- tryCatch(read_raw_bytes(path), error = function(e) raw())
  if (any(receipt_bytes == as.raw(0))) return(FALSE)
  receipt_text <- tryCatch(rawToChar(receipt_bytes), error = function(e) "")
  receipt <- tryCatch(jsonlite::parse_json(receipt_text, simplifyVector = FALSE),
    error = function(e) NULL)
  valid_study_receipt(receipt, current_commit, reference_study)
}
