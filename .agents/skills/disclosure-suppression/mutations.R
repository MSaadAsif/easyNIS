#!/usr/bin/env Rscript

check_mutations <- function() {
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  scratch <- tempfile("easynis-disclosure-mutations-", tmpdir = parent)
  stopifnot(dir.create(scratch, mode = "0700"))
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  on.exit({
    stopifnot(identical(dirname(scratch), parent),
      identical(normalizePath(scratch, winslash = "/", mustWork = TRUE), scratch))
    unlink(scratch, recursive = TRUE)
    stopifnot(!file.exists(scratch))
    cat("MUTATION SCRATCH REMOVED\n")
  })

  archive <- file.path(scratch, "source.zip")
  status <- system2("git", c("archive", "--format=zip", "-o", shQuote(archive), "HEAD"))
  stopifnot(status == 0L)
  source_dir <- file.path(scratch, "source")
  utils::unzip(archive, exdir = source_dir)
  unlink(archive)
  rscript <- file.path(R.home("bin"), "Rscript")

  mutations <- list(
    threshold = c("R/disclosure-policy.R", "counts <= threshold", "counts < threshold"),
    hospitals = c("R/disclosure-policy.R", "hospitals < 2L", "hospitals < 1L"),
    complementary = c("R/suppress-data-frame.R", "if (args$secondary) {", "if (FALSE) {"),
    weighted = c("R/suppress-data-frame.R", "args$count_col, args$weighted_cols, args$hospital_col",
      "args$count_col, args$hospital_col")
  )

  for (name in names(mutations)) {
    mutation <- mutations[[name]]
    path <- file.path(source_dir, mutation[[1L]])
    original <- readLines(path, warn = FALSE)
    stopifnot(sum(grepl(mutation[[2L]], original, fixed = TRUE)) == 1L)
    writeLines(sub(mutation[[2L]], mutation[[3L]], original, fixed = TRUE), path)
    cat("MUTATION ", name, " ", mutation[[1L]], " \"", mutation[[2L]], "\" -> \"",
      mutation[[3L]], "\"\n", sep = "")

    output <- file.path(scratch, "child.txt")
    status <- system2(rscript, c("--vanilla", ".agents/skills/disclosure-suppression/check.R",
      shQuote(source_dir)), stdout = output, stderr = output)
    writeLines(original, path)
    lines <- readLines(output, warn = FALSE)
    evidence <- sub("^EVIDENCE ", "", grep("^EVIDENCE ", lines, value = TRUE))
    if (status != 1L || length(evidence) != 1L ||
        !any(startsWith(lines, "RESULT FAIL Disclosure counterexample.")) ||
        !file.exists(file.path(evidence, "counterexample.R")) ||
        !any(startsWith(lines, "CLEANUP PASS "))) {
      cat(lines, sep = "\n")
      stop("Mutation did not fail and clean up as expected: ", name)
    }
    cat("MUTATION CAUGHT ", name, " ", evidence, "\n", sep = "")
  }
}

check_mutations()
