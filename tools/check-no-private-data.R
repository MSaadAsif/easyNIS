#!/usr/bin/env Rscript

read_git_index <- function(file) {
  run_git(c("ls-files", "--stage", "-z"), stdout = file)
  bytes <- readBin(file, "raw", n = file.size(file))
  ends <- which(bytes == as.raw(0L))
  starts <- head(c(0L, ends), -1L) + 1L
  entries <- Map(function(start, end) rawToChar(bytes[start:(end - 1L)]), starts, ends)
  pattern <- "^([0-7]{6}) ([0-9a-f]+) ([0-3])\t"
  entries <- unlist(entries, use.names = FALSE)
  if (length(entries) && any(!grepl(pattern, entries))) stop("Could not parse the Git index.")
  header_end <- regexpr("\t", entries, fixed = TRUE)
  metadata <- substring(entries, 1L, header_end - 1L)
  index <- data.frame(
    path = substring(entries, header_end + 1L),
    id = sub("^.{7}([0-9a-f]+) [0-3]$", "\\1", metadata),
    mode = substr(metadata, 1L, 6L)
  )
  if (anyDuplicated(index$path)) stop("Resolve unmerged paths before running the private-data guard.")
  index[index$mode != "160000", , drop = FALSE]
}

run_git <- function(args, ...) {
  result <- system2("git", c("--no-replace-objects", args), ...)
  if (!identical(result, 0L)) stop("Could not inspect the Git index.", call. = FALSE)
  invisible(NULL)
}

staged_blob_sizes <- function(ids, input, output) {
  writeLines(ids, input)
  run_git(c("cat-file", "--batch-check"), stdin = input, stdout = output)
  metadata <- strsplit(readLines(output, warn = FALSE), " ", fixed = TRUE)
  valid <- length(metadata) == length(ids) && all(lengths(metadata) == 3L)
  if (!valid) stop("Could not read staged blob sizes.", call. = FALSE)
  entries <- do.call(rbind, metadata)
  sizes <- suppressWarnings(as.numeric(entries[, 3L]))
  if (!identical(unname(entries[, 1L]), ids) ||
      any(entries[, 2L] != "blob") || any(!is.finite(sizes))) {
    stop("Could not verify staged blob sizes.", call. = FALSE)
  }
  stats::setNames(sizes, ids)
}

scan_staged_blobs <- function(sizes, input, output, markers) {
  if (!length(sizes)) return(list())
  writeLines(names(sizes), input)
  run_git(c("cat-file", "--batch"), stdin = input, stdout = output)
  connection <- file(output, "rb")
  on.exit(close(connection), add = TRUE)
  stats::setNames(Map(function(id, size) {
    header <- ""
    byte <- readBin(connection, "raw", n = 1L)
    while (length(byte) && byte != as.raw(10L)) {
      header <- paste0(header, rawToChar(byte))
      byte <- readBin(connection, "raw", n = 1L)
    }
    if (!length(byte) || !identical(header, sprintf("%s blob %.0f", id, size))) {
      stop("Could not read a staged blob header.", call. = FALSE)
    }
    bytes <- readBin(connection, "raw", n = size)
    end <- readBin(connection, "raw", n = 1L)
    if (length(bytes) != size || !identical(end, as.raw(10L))) {
      stop("Could not read a complete staged blob.", call. = FALSE)
    }
    bytes[bytes == as.raw(0L)] <- as.raw(32L)
    markers[vapply(markers, grepl, logical(1), x = rawToChar(bytes),
      fixed = TRUE, useBytes = TRUE)]
  }, names(sizes), sizes), names(sizes))
}

data_extension <- "\\.(parquet|dta|sas7bdat|sav|rds|rda|rdata|fst|feather|duckdb|asc)$"
separator <- intToUtf8(92L)
private_strings <- c(
  paste0("C:/", "Users/"),
  paste0("C:", separator, "Users", separator),
  paste0("C:", separator, separator, "Users", separator, separator),
  paste0("AHRQ_", "NIS"),
  paste0("RCOP_", "NIS")
)

check_private_data <- function() {
  root <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE)
  if (length(root) != 1L || !nzchar(root)) stop("Run this script from inside a Git repository.")
  setwd(root)
  input <- tempfile("easyNIS-index-input-")
  output <- tempfile("easyNIS-index-output-")
  on.exit(unlink(c(input, output)), add = TRUE)
  index <- read_git_index(output)
  if (!nrow(index)) return(character())
  sizes <- staged_blob_sizes(unique(index$id), input, output)
  limit <- 1000000
  large <- unname(sizes[index$id]) > limit
  marked <- scan_staged_blobs(sizes[sizes <= limit], input, output, private_strings)
  paths <- index$path
  synthetic <- grepl("^inst/extdata/synthetic(/|$)", paths)
  data_file <- !synthetic & grepl(data_extension, paths, ignore.case = TRUE)
  findings <- c(
    sprintf("data extension: %s", paths[data_file]),
    sprintf("larger than 1 MB (%0.2f MB): %s", sizes[index$id[large]] / limit, paths[large])
  )
  for (i in which(!large)) {
    hits <- marked[[index$id[[i]]]]
    if (length(hits)) {
      findings <- c(findings, sprintf("private path or directory marker (%s): %s",
        paste(hits, collapse = ", "), paths[[i]]))
    }
  }
  if (!length(findings)) message(sprintf("Private-data guard passed: checked %d index files.", nrow(index)))
  findings
}

findings <- check_private_data()
if (length(findings)) {
  cat("Private-data guard failed:\n", paste0("- ", findings, collapse = "\n"), "\n", sep = "")
  quit(status = 1L)
}
