valid_named_fields <- function(value, required) {
  is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) && all(required %in% names(value))
}

valid_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

valid_study_number <- function(value) {
  is.numeric(value) && length(value) == 1L && is.finite(value) && value > 0
}

valid_reference_study <- function(study) {
  fields <- c("id", "citation", "url", "location", "definition", "tolerance", "rounding")
  valid_named_fields(study, fields) &&
    all(vapply(study[setdiff(fields, "tolerance")], valid_nonempty_string, logical(1))) &&
    grepl("^https://", study$url) &&
    valid_study_number(study$tolerance)
}

valid_reference_studies <- function(studies) {
  is.list(studies) &&
    length(studies) == 3L &&
    all(vapply(studies, valid_reference_study, logical(1))) &&
    !anyDuplicated(vapply(studies, `[[`, character(1), "id"))
}

load_reference_studies <- function(path) {
  reference <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (is.list(reference)) reference[["studies"]]
}

read_study_json <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  bytes <- tryCatch(suppressWarnings(read_raw_bytes(path)), error = function(e) raw())
  if (!length(bytes) || any(bytes == as.raw(0))) {
    return(NULL)
  }
  tryCatch(jsonlite::parse_json(rawToChar(bytes), simplifyVector = FALSE), error = function(e) NULL)
}

valid_study_references <- function(references, ids) {
  valid_named_fields(references, ids) &&
    length(references) == length(ids) &&
    all(vapply(references, valid_study_number, logical(1)))
}

study_receipt_path <- function(loop_dir, commit) {
  file.path(loop_dir, "private", "study-verification", paste0(commit, ".json"))
}

study_reference_path <- function(loop_dir) {
  file.path(loop_dir, "private", "study-verification", "references.json")
}

study_verification_results <- function(path, commit, studies, references) {
  if (!valid_reference_studies(studies)) {
    return(NULL)
  }
  ids <- vapply(studies, `[[`, character(1), "id")
  if (!valid_study_references(references, ids)) {
    return(NULL)
  }
  receipt <- read_study_json(path)
  if (
    !valid_named_fields(receipt, c("package_commit_hash", "results")) ||
      !identical(receipt$package_commit_hash, commit) ||
      !valid_named_fields(receipt$results, ids) ||
      length(receipt$results) != length(ids)
  ) {
    return(NULL)
  }
  differences <- vapply(
    ids,
    function(id) {
      result <- receipt$results[[id]]
      reference <- references[[id]]
      if (
        !valid_named_fields(result, c("estimate", "reference")) ||
          !valid_study_number(result$estimate) ||
          !valid_study_number(result$reference) ||
          result$reference != reference
      ) {
        return(NA_real_)
      }
      abs(result$estimate - reference) / reference
    },
    numeric(1)
  )
  if (!all(is.finite(differences))) {
    return(NULL)
  }
  tolerance <- vapply(studies, `[[`, numeric(1), "tolerance")
  data.frame(
    id = ids,
    status = ifelse(unname(differences) <= tolerance, "pass", "fail"),
    relative_error = unname(differences),
    tolerance = tolerance
  )
}

study_verification_summary <- function(results) {
  if (is.null(results)) {
    return("Requires three local study comparisons matched to the current commit")
  }
  percent <- function(value) paste0(trimws(formatC(100 * value, format = "g", digits = 1)), "%")
  resolution <- pmin(results$tolerance, 0.000001)
  difference <- ifelse(
    results$relative_error < resolution,
    paste0("<", percent(resolution)),
    paste0("~", percent(results$relative_error))
  )
  paste(paste0(results$id, " ", results$status, " (", difference, " relative error)"), collapse = ", ")
}
