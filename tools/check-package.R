#!/usr/bin/env Rscript

check_committed_package <- function() {
  commit <- system2("git", c("rev-parse", "--verify", "HEAD"), stdout = TRUE)
  if (length(commit) != 1L || !grepl("^[0-9a-f]{40,64}$", commit)) {
    stop("Could not identify the committed package source.")
  }
  cat("CHECK_COMMIT ", commit, "\n", sep = "")
  temp <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  scratch <- tempfile("easynis-package-check-", tmpdir = temp)
  if (!dir.create(scratch, mode = "0700")) stop("Could not create the check workspace.")
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  on.exit({
    if (identical(dirname(scratch), temp) &&
        identical(normalizePath(scratch, winslash = "/", mustWork = TRUE), scratch)) {
      unlink(scratch, recursive = TRUE)
    }
    if (file.exists(scratch)) stop("Could not remove the check workspace.")
  })

  archive <- file.path(scratch, "source.zip")
  status <- system2("git", c("archive", "--format=zip", "-o", shQuote(archive), commit))
  if (status != 0L) stop("Could not archive the committed source.")
  source <- file.path(scratch, "easyNIS")
  utils::unzip(archive, exdir = source)
  unlink(archive)
  result <- devtools::check(pkg = source, document = FALSE, args = "--no-manual", error_on = "never")
  counts <- c(length(result$errors), length(result$warnings), length(result$notes))
  cat("CHECK_COUNTS", counts, "\n")
  as.integer(any(counts != 0L))
}

quit(status = check_committed_package())
