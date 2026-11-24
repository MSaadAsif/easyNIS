redact_paths <- function(text) {
  text <- as.character(text)
  text <- gsub("(?i)\\b[A-Z]:[/\\\\][^\\r\\n]*", "[local path]", text, perl = TRUE)
  text <- gsub("(?<!:)//[^\\r\\n]*", "[local path]", text, perl = TRUE)
  text <- gsub("(?i)\\\\\\\\[^\\r\\n]*", "[local path]", text, perl = TRUE)
  gsub("(?<![A-Za-z0-9_:/])/(?!/)[^\\r\\n]*", "[local path]", text, perl = TRUE)
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
