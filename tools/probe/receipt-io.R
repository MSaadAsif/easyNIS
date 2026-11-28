valid_named_fields <- function(value, required) {
  is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) && all(required %in% names(value))
}

valid_nonempty_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

read_raw_bytes <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection))
  readBin(connection, what = "raw", n = file.info(path)$size)
}
