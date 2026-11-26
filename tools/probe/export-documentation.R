exported_example_status <- function(root = ".") {
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\(([^)]+)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  has_examples <- vapply(
    exports,
    function(name) {
      file <- file.path(root, "man", paste0(name, ".Rd"))
      if (!file.exists(file)) {
        return(FALSE)
      }
      lines <- readLines(file, warn = FALSE)
      example_start <- grep("^\\\\examples\\s*\\{", lines, perl = TRUE)
      if (!length(example_start)) {
        return(FALSE)
      }
      block <- paste(lines[example_start[[1L]]:length(lines)], collapse = "\n")
      !grepl("^\\\\examples\\s*\\{\\s*\\\\dontrun\\s*\\{", block, perl = TRUE)
    },
    logical(1)
  )
  list(exports = exports, has_examples = has_examples)
}
