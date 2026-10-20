#!/usr/bin/env Rscript

root <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE)
if (length(root) != 1L || !nzchar(root)) {
  stop("Run this script from inside a Git repository.", call. = FALSE)
}
setwd(root)

index_file <- tempfile("easyNIS-index-")
on.exit(unlink(index_file), add = TRUE)
status <- system2("git", c("ls-files", "--cached", "-z"), stdout = index_file)
if (!identical(status, 0L)) {
  stop("Could not list tracked and staged files.", call. = FALSE)
}
paths_raw <- readBin(index_file, what = "raw", n = file.info(index_file)$size)
if (!length(paths_raw)) {
  message("Private-data guard passed: no tracked or staged files.")
  quit(status = 0L)
}
separators <- which(paths_raw == as.raw(0L))
starts <- c(1L, head(separators, -1L) + 1L)
paths <- vapply(seq_along(separators), function(i) {
  rawToChar(paths_raw[starts[i]:(separators[i] - 1L)])
}, character(1L), USE.NAMES = FALSE)

data_extension <- "\\.(parquet|dta|sas7bdat|sav|rds|rda|rdata|fst|feather|duckdb|asc)$"
synthetic_fixture <- grepl("^inst/extdata/synthetic(/|$)", paths)
separator <- intToUtf8(92L)
private_strings <- c(
  paste0("C:/", "Users/"),
  paste0("C:", separator, "Users", separator),
  paste0("C:", separator, separator, "Users", separator, separator),
  paste0("AHRQ_", "NIS"),
  paste0("nis_", "data"),
  paste0("RCOP_", "NIS")
)

findings <- character()
for (i in seq_along(paths)) {
  path <- paths[[i]]
  if (!file.exists(path) || dir.exists(path)) next

  normalized <- gsub("\\\\", "/", path)
  if (!synthetic_fixture[[i]] && grepl(data_extension, normalized, ignore.case = TRUE)) {
    findings <- c(findings, sprintf("data extension: %s", path))
  }

  size <- file.info(path)$size
  if (is.finite(size) && size > 1e6) {
    findings <- c(findings, sprintf("larger than 1 MB (%0.2f MB): %s", size / 1e6, path))
    next
  }

  bytes <- readBin(path, what = "raw", n = size)
  if (length(bytes)) {
    bytes[bytes == as.raw(0L)] <- as.raw(32L)
    contents <- rawToChar(bytes)
    hits <- vapply(private_strings, grepl, logical(1L), x = contents, fixed = TRUE)
    if (any(hits)) {
      findings <- c(findings, sprintf("private path or directory marker (%s): %s",
                                      paste(private_strings[hits], collapse = ", "), path))
    }
  }
}

if (length(findings)) {
  cat("Private-data guard failed:\n", paste0("- ", findings, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
message(sprintf("Private-data guard passed: checked %d tracked/staged files.", length(paths)))
