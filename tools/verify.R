args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) && args != "--doctor")) {
  stop("Usage: Rscript tools/verify.R [--doctor]")
}
if (!file.exists("DESCRIPTION") || !file.exists("tools/check-tarball.R")) {
  stop("Run from the easyNIS package repository.")
}
required <- c("DBI", "duckdb", "testthat", "pkgload", "roxygen2", "arrow")
available <- vapply(required, requireNamespace, logical(1), quietly = TRUE)
if (!all(available)) stop("Missing development packages: ", paste(required[!available], collapse = ", "))
description <- read.dcf("DESCRIPTION")
generator <- unname(description[1L, "Config/roxygen2/version"])
if (as.character(utils::packageVersion("roxygen2")) != generator) {
  stop("Install roxygen2 ", generator, " to match DESCRIPTION and CI.")
}
cat(R.version.string, "\n")
for (package in required) cat(package, as.character(utils::packageVersion(package)), "\n")
if (length(args)) quit(status = 0L)

output <- tempfile(paste0(format(Sys.time(), "%Y%m%dT%H%M%S"), "-"), ".audit/verify")
dir.create(output, recursive = TRUE)
output <- normalizePath(output, winslash = "/")
cat("Evidence directory:", output, "\n")
writeLines(c(paste("R:", R.version.string), capture.output(utils::sessionInfo())),
           file.path(output, "session.txt"))
git_head <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
writeLines(git_head, file.path(output, "head.txt"))
writeLines(system2("git", c("status", "--porcelain"), stdout = TRUE),
           file.path(output, "working-tree.txt"))
source_files <- unique(system2("git", c("-c", "core.quotepath=false", "ls-files",
                                       "--cached", "--others", "--exclude-standard"), stdout = TRUE))
source_files <- source_files[file.exists(source_files)]
write.table(data.frame(path = source_files, md5 = unname(tools::md5sum(source_files))),
            file.path(output, "source-fingerprints.tsv"), sep = "\t", row.names = FALSE)
generated <- c("DESCRIPTION", "NAMESPACE", list.files("man", full.names = TRUE))
before <- tools::md5sum(generated)
roxygen2::roxygenise()
after_files <- c("DESCRIPTION", "NAMESPACE", list.files("man", full.names = TRUE))
if (!identical(before, tools::md5sum(after_files))) {
  stop("Generated documentation changed. Review it, then rerun verification.")
}
verify_tests <- function(results, name) {
  rows <- as.data.frame(results)
  rows <- rows[vapply(rows, is.atomic, logical(1))]
  utils::write.csv(rows, file.path(output, paste0(name, ".csv")), row.names = FALSE)
  if (!nrow(rows) || any(rows$failed > 0L | rows$error | rows$warning > 0L | rows$skipped)) {
    stop(name, " has failures, errors, warnings, skips, or no cases.")
  }
  sum(rows$passed)
}
package_assertions <- verify_tests(testthat::test_local(reporter = "summary"), "package-tests")
tool_assertions <- verify_tests(testthat::test_dir("tools/tests", reporter = "summary"), "tool-tests")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
run <- function(command, arguments, log) {
  status <- system2(command, arguments, stdout = file.path(output, log), stderr = file.path(output, log))
  if (status != 0L) stop(log, " failed with exit ", status, ". Evidence: ", output)
}
root <- normalizePath(".", winslash = "/")
build <- file.path(output, "build")
dir.create(build)
stage <- tempfile("easynis-source-")
dir.create(stage)
tracked <- system2("git", c("-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard"), stdout = TRUE)
tracked <- unique(tracked[file.exists(tracked)])
for (file in tracked) {
  target <- file.path(stage, file)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(file, target, copy.date = TRUE)) stop("Failed to stage source: ", file)
}
setwd(build)
tryCatch(run(r, c("CMD", "build", shQuote(stage)), "build.log"),
         finally = { setwd(root); unlink(stage, recursive = TRUE) })
tarballs <- list.files(build, "[.]tar[.]gz$", full.names = TRUE)
if (length(tarballs) != 1L) stop("Expected exactly one newly built source tarball.")
writeLines(unname(tools::md5sum(tarballs)), file.path(output, "source-tarball-md5.txt"))
run(rscript, c("tools/check-tarball.R", shQuote(tarballs)), "tarball.log")
run(r, c("CMD", "check", "--no-manual", paste0("--output=", shQuote(output)), shQuote(tarballs)), "check.log")
check_logs <- list.files(output, "00check[.]log$", recursive = TRUE, full.names = TRUE)
if (length(check_logs) != 1L || !any(readLines(check_logs) == "Status: OK")) {
  stop("R CMD check did not report Status: OK. Evidence: ", output)
}
library <- file.path(output, "library")
dir.create(library)
run(r, c("CMD", "INSTALL", paste0("--library=", shQuote(library)), shQuote(tarballs)), "install.log")
run(rscript, c("tools/smoke-installed.R", shQuote(library)), "installed-workflow.log")
writeLines(c("VERIFIED", paste("head:", git_head),
             paste("package assertions:", package_assertions),
             paste("tool assertions:", tool_assertions),
             "source check: Status OK", "installed public workflow: passed",
             "annual and scientific approval: unchanged"), file.path(output, "summary.txt"))
cat(readLines(file.path(output, "summary.txt")), sep = "\n")
