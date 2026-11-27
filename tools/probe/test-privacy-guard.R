local({
  guard <- normalizePath("tools/check-no-private-data.R", winslash = "/", mustWork = TRUE)
  directory <- tempfile("privacy-fixture-")
  stopifnot(dir.create(directory))
  previous <- setwd(directory)
  on.exit(
    {
      setwd(previous)
      unlink(directory, recursive = TRUE)
    },
    add = TRUE
  )
  git <- function(...) {
    status <- system2("git", c(...), stdout = FALSE, stderr = FALSE)
    stopifnot(identical(status, 0L))
  }
  inspect <- function() {
    output <- suppressWarnings(system2(
      file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(guard)),
      stdout = TRUE,
      stderr = TRUE
    ))
    list(output = output, status = attr(output, "status", exact = TRUE))
  }

  git("init", "--quiet")
  writeLines(paste0("AHRQ_", "NIS"), "invented.txt")
  git("add", "--", "invented.txt")
  writeLines("benign worktree", "invented.txt")
  blocked <- inspect()
  stopifnot(identical(blocked$status, 1L), any(grepl("private path or directory marker", blocked$output, fixed = TRUE)))

  git("add", "--", "invented.txt")
  writeLines(paste0("AHRQ_", "NIS"), "invented.txt")
  stopifnot(is.null(inspect()$status))

  writeBin(rep(as.raw(65L), 100000L), "bytes.txt")
  git("add", "--", "bytes.txt")
  stopifnot(is.null(inspect()$status))

  writeLines("invented", "missing.parquet")
  git("add", "--", "missing.parquet")
  unlink("missing.parquet")
  blocked <- inspect()
  stopifnot(identical(blocked$status, 1L), any(grepl("data extension: missing.parquet", blocked$output, fixed = TRUE)))
  git("rm", "--cached", "--", "missing.parquet")

  dir.create("inst/ccsr", recursive = TRUE)
  reference <- c("inst/ccsr/map.parquet", "inst/ccsr/categories.parquet")
  for (file in reference) {
    writeLines("invented", file)
  }
  git("add", "--", reference)
  stopifnot(is.null(inspect()$status))

  other <- "inst/ccsr/other.parquet"
  writeLines("invented", other)
  git("add", "--", other)
  blocked <- inspect()
  stopifnot(identical(blocked$status, 1L), any(grepl(paste("data extension:", other), blocked$output, fixed = TRUE)))

  writeLines(paste0("AHRQ_", "NIS"), reference[1L])
  git("add", "--", reference[1L])
  blocked <- inspect()
  stopifnot(identical(blocked$status, 1L), any(grepl("private path or directory marker", blocked$output, fixed = TRUE)))
})
cat("Privacy-guard tests passed.\n")
