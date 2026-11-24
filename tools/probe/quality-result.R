pkgcheck_pass <- function(value) {
  # No published aggregate pass API; retain known nested failures only.
  if (!inherits(value, "pkgcheck")) return(NA)
  if (identical(goodpractice_pass(value$goodpractice), FALSE)) return(FALSE)
  NA
}
check_counts_for <- function(value) {
  has_counts <- is.list(value) && all(c("errors", "warnings", "notes") %in% names(value))
  if (inherits(value, "rcmdcheck") || has_counts) return(check_result_counts(value))
  NULL
}
quality_step_pass <- function(x, definition, counts) {
  value <- x$value
  if (identical(value, "skipped_by_selection") || identical(value, "not installed")) return(NA)
  if (inherits(value, "error")) return(FALSE)
  if (!is.null(definition$pass)) return(definition$pass(x))
  if (!is.null(counts)) return(x$pass && all(counts == 0L))
  isTRUE(x$pass)
}
quality_step_status <- function(value, passed) {
  if (identical(value, "skipped_by_selection")) return("skipped_by_selection")
  if (identical(value, "not installed")) return("skipped_not_installed")
  if (inherits(value, "error")) return("failed")
  if (is.na(passed)) return("not_verified")
  "completed"
}
lint_detail <- function(value) {
  lint_table <- tryCatch(as.data.frame(value), error = function(e) NULL)
  columns <- c("filename", "line_number", "column_number", "message")
  if (!is.data.frame(lint_table) || !all(columns %in% names(lint_table))) {
    return(paste(capture.output(print(value)), collapse = " | "))
  }
  file <- gsub("^.*[/\\\\](R|tests)[/\\\\]", "\\1/", lint_table$filename, perl = TRUE)
  entries <- paste0(file, ":", lint_table$line_number, ":", lint_table$column_number,
    ": ", lint_table$message)
  paste(vapply(entries, redact_paths, character(1)), collapse = " | ")
}
quality_step_detail <- function(x, definition, counts, passed) {
  if (inherits(x$value, "error")) return(x$error)
  if (!is.null(definition$detail)) return(definition$detail(x, passed))
  if (!is.null(counts)) return(paste(names(counts), counts, collapse = " | "))
  ""
}

quality_record <- function(x, evidence) {
  value <- x$value
  counts <- check_counts_for(value)
  definition <- quality_definition(x$name)
  provenance <- definition$provenance
  passed <- provenance_pass(quality_step_pass(x, definition, counts), provenance)
  detail <- quality_step_detail(x, definition, counts, passed)
  if (definition$redact_detail) detail <- redact_paths(detail)
  record <- quality_receipt_record(x, evidence, quality_step_status(value, passed), passed, detail)
  record$provenance <- if (inherits(value, "error")) "failed" else if (
    identical(value, "skipped_by_selection") || identical(value, "not installed")
  ) "not_measured" else provenance
  record
}
