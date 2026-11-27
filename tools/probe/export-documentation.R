exported_example_status <- function(root = ".") {
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\(([^)]+)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  topics <- list.files(file.path(root, "man"), pattern = "[.]Rd$", full.names = TRUE)
  runnable_aliases <- lapply(
    topics,
    function(file) {
      lines <- readLines(file, warn = FALSE)
      example_start <- grep("^\\\\examples\\s*\\{", lines, perl = TRUE)
      if (!length(example_start)) {
        return(character())
      }
      block <- paste(lines[example_start[[1L]]:length(lines)], collapse = "\n")
      if (grepl("^\\\\examples\\s*\\{\\s*\\\\dontrun\\s*\\{", block, perl = TRUE)) {
        return(character())
      }
      aliases <- grep("^\\\\alias\\{", lines, value = TRUE)
      sub("^\\\\alias\\{([^}]+)\\}$", "\\1", aliases)
    }
  )
  has_examples <- stats::setNames(exports %in% unlist(runnable_aliases, use.names = FALSE), exports)
  list(exports = exports, has_examples = has_examples)
}
