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

valid_study_record <- function(study) {
  required <- c("id", "pass", "tolerance")
  if (!is.list(study) || !all(required %in% names(study))) return(FALSE)
  is.character(study$id) && length(study$id) == 1L && nzchar(study$id) &&
    identical(study$pass, TRUE) && is.numeric(study$tolerance) &&
    length(study$tolerance) == 1L && is.finite(study$tolerance) && study$tolerance >= 0
}

valid_study_records <- function(studies) {
  if (!is.list(studies) || length(studies) != 3L) return(FALSE)
  if (!all(vapply(studies, valid_study_record, logical(1)))) return(FALSE)
  ids <- vapply(studies, `[[`, character(1), "id")
  all(nzchar(ids)) && !anyDuplicated(ids)
}

study_verification_ready <- function(path, current_commit) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) return(FALSE)
  receipt <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL)
  is.list(receipt) && identical(receipt$commit, current_commit) &&
    valid_receipt_time(receipt$verified_at) && valid_study_records(receipt$studies)
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
