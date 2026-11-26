#!/usr/bin/env Rscript

check_committed_package <- function() {
  commit <- system2("git", c("rev-parse", "--verify", "HEAD"), stdout = TRUE)
  if (length(commit) != 1L || !grepl("^[0-9a-f]{40,64}$", commit)) {
    stop("Could not identify the committed package source.")
  }
  cat("CHECK_COMMIT ", commit, "\n", sep = "")
  temp <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  scratch <- tempfile("easynis-package-check-", tmpdir = temp)
  if (!dir.create(scratch, mode = "0700")) {
    stop("Could not create the check workspace.")
  }
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  on.exit({
    if (
      identical(dirname(scratch), temp) &&
        identical(normalizePath(scratch, winslash = "/", mustWork = TRUE), scratch)
    ) {
      unlink(scratch, recursive = TRUE)
    }
    if (file.exists(scratch)) stop("Could not remove the check workspace.")
  })

  archive <- file.path(scratch, "source.zip")
  status <- system2("git", c("archive", "--format=zip", "-o", shQuote(archive), commit))
  if (status != 0L) {
    stop("Could not archive the committed source.")
  }
  source <- file.path(scratch, "easyNIS")
  utils::unzip(archive, exdir = source)
  unlink(archive)
  result <- devtools::check(pkg = source, document = FALSE, args = "--no-manual", error_on = "never")
  counts <- c(length(result$errors), length(result$warnings), length(result$notes))
  cat("CHECK_COUNTS", counts, "\n")
  as.integer(any(counts != 0L))
}

check_complexity <- function() {
  source(file.path("tools", "probe", "provenance.R"))
  scores <- namespace_complexity(".")
  passed <- namespace_complexity_pass(scores)
  if (is.na(passed)) {
    stop("Could not verify installed package complexity.", call. = FALSE)
  }
  cat("Maximum cyclomatic complexity:", max(scores$cyclocomp), "(limit 15)\n")
  if (!passed) {
    print(scores[scores$cyclocomp > 15, , drop = FALSE])
  }
  as.integer(!passed)
}

check_lint <- function() {
  commands <- list(air = c("format", ".", "--check"), jarl = c("check", "."))
  for (command in names(commands)) {
    executable <- Sys.which(command)
    if (!nzchar(executable)) {
      stop("Install ", command, " and add it to PATH. See CONTRIBUTING.md.", call. = FALSE)
    }
    status <- system2(executable, commands[[command]])
    if (status != 0L) {
      return(status)
    }
  }
  check_complexity()
}

args <- commandArgs(trailingOnly = TRUE)
status <- if (length(args) == 0L) {
  check_committed_package()
} else if (identical(args, "--lint")) {
  check_lint()
} else if (identical(args, "--complexity")) {
  check_complexity()
} else {
  stop("Usage: Rscript --vanilla tools/check-package.R [--lint | --complexity]", call. = FALSE)
}
quit(status = status)
