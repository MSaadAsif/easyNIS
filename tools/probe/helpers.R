find_main_repo <- function(start = ".") {
  common_dir <- tryCatch(suppressWarnings(system2("git",
    c("rev-parse", "--git-common-dir"), stdout = TRUE, stderr = FALSE)),
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
  if (file.exists(path)) readRenviron(path)
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

study_verification_ready <- function(path) {
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) return(FALSE)
  receipt <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL)
  if (!is.list(receipt) || is.null(receipt$studies) ||
      !is.list(receipt$studies) || length(receipt$studies) != 3L) return(FALSE)
  valid_study <- function(study) {
    if (!is.list(study) || !all(c("id", "pass", "tolerance") %in% names(study))) return(FALSE)
    is.character(study$id) && length(study$id) == 1L && nzchar(study$id) &&
      identical(study$pass, TRUE) && is.numeric(study$tolerance) &&
      length(study$tolerance) == 1L && is.finite(study$tolerance) && study$tolerance >= 0
  }
  if (!all(vapply(receipt$studies, valid_study, logical(1)))) return(FALSE)
  study_ids <- vapply(receipt$studies, function(study) {
    study$id
  }, character(1))
  if (any(!nzchar(study_ids)) || anyDuplicated(study_ids)) return(FALSE)
  TRUE
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

exported_example_status <- function(root = ".") {
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\(([^)]+)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  has_examples <- vapply(exports, function(name) {
    file <- file.path(root, "man", paste0(name, ".Rd"))
    file.exists(file) && any(grepl("\\\\examples\\{", readLines(file, warn = FALSE)))
  }, logical(1))
  list(exports = exports, has_examples = has_examples)
}
