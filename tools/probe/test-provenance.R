source("tools/probe/provenance.R")
local({
  scratch <- tempfile("quality-fixture-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  make_package <- function(path, definition) {
    dir.create(file.path(path, "R"), recursive = TRUE)
    writeLines(c("Package: qualityprovenancefixture", "Version: 0.0.1",
      "Title: Invented Fixture", "Description: An invented test fixture.",
      "License: MIT", "Author: Fixture Author",
      "Maintainer: Fixture Author <fixture@example.org>"), file.path(path, "DESCRIPTION"))
    writeLines("export(marker)", file.path(path, "NAMESPACE"))
    writeLines(definition, file.path(path, "R", "marker.R"))
  }
  older <- file.path(scratch, "older")
  requested <- file.path(scratch, "requested")
  broken <- file.path(scratch, "broken")
  library <- file.path(scratch, "library")
  dir.create(library)
  make_package(older, 'marker <- function() "older"')
  make_package(requested, 'marker <- function(x = TRUE) { if (x) "requested" else "other" }')
  make_package(broken, 'marker <- function( {')
  callr::rcmd("INSTALL", c(paste0("--library=", library), older), fail_on_status = TRUE)
  previous <- .libPaths()
  on.exit(.libPaths(previous), add = TRUE)
  .libPaths(c(library, previous))
  pkgload::load_all(requested, quiet = TRUE)
  on.exit(pkgload::unload("qualityprovenancefixture"), add = TRUE)
  # An older installation with the same version remains available on failure.
  failed <- tryCatch(with_verified_source(broken, function(root, package) {
    stop("Callback must never run after failed installation")
  }), error = identity)
  stopifnot(inherits(failed, "error"), !grepl("Callback must never", conditionMessage(failed)))
  cat("Install failure refused before callback\n")
  result <- with_verified_source(requested, function(root, package) {
    list(marker = getExportedValue(package, "marker")(),
      complexity = cyclocomp::cyclocomp_package(package)$cyclocomp,
      version = as.character(utils::packageVersion(package)))
  })
  stopifnot(identical(result$marker, "requested"), result$complexity == 2,
    result$version == "0.0.1")
  cat("Loaded parent / same-version fallback: isolated requested namespace measured\n")
})
stopifnot(identical(provenance_pass(FALSE, "nested_unverified"), FALSE),
  is.na(provenance_pass(TRUE, "nested_unverified")),
  is.na(provenance_pass(NA, "nested_unverified")),
  identical(provenance_pass(TRUE, "isolated_namespace_verified"), TRUE),
  is.na(provenance_pass(NA, "isolated_namespace_verified")))
cat("Provenance behavior tests passed\n")
# Exercise the production receipt reducer without executing the probe entry point.
source("tools/probe/helpers.R")
probe <- parse("tools/probe/probe-quality.R")
for (expression in probe) {
  if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
      is.symbol(expression[[2L]]) &&
      as.character(expression[[2L]]) %in% c("pkgcheck_pass", "check_counts_for",
        "quality_step_pass", "quality_step_status", "lint_detail",
        "quality_step_detail", "quality_record")) eval(expression)
}
evidence <- list(commit = "invented", working_tree_clean = TRUE)
receipt <- function(name, fn) quality_record(capture_quality_step(name, fn), evidence)
check <- receipt("R CMD check --as-cran", function() list(errors = character(),
  warnings = character(), notes = character()))
stopifnot(is.na(check$pass), check$status == "not_verified",
  check$provenance == "nested_unverified")
failed <- receipt("R CMD check --as-cran", function() list(errors = "invented failure",
  warnings = character(), notes = character()))
stopifnot(identical(failed$pass, FALSE))
failed_install <- receipt("installed_namespace_complexity", function() stop("invented failure"))
stopifnot(identical(failed_install$pass, FALSE), failed_install$status == "failed",
  failed_install$provenance == "failed")
measured <- receipt("installed_namespace_complexity", function() data.frame(name = "marker", cyclocomp = 2))
stopifnot(isTRUE(measured$pass), measured$provenance == "isolated_namespace_verified")
unknown <- receipt("pkgcheck", function() structure(list(), class = "pkgcheck"))
stopifnot(is.na(unknown$pass), unknown$status == "not_verified")
cat("Production receipt provenance tests passed\n")
stopifnot(is.na(namespace_complexity_pass(NULL)),
  is.na(namespace_complexity_pass(data.frame(cyclocomp = numeric()))),
  is.na(namespace_complexity_pass(data.frame(cyclocomp = NA_real_))),
  identical(namespace_complexity_pass(data.frame(cyclocomp = 16)), FALSE))
skipped <- receipt("installed_namespace_complexity", function() "skipped_by_selection")
stopifnot(is.na(skipped$pass), skipped$provenance == "not_measured")
gp_failure <- structure(list(checks = list(invented = list(status = FALSE))), class = "goodPractice")
gp_receipt <- receipt("goodpractice", function() gp_failure)
pkg_receipt <- receipt("pkgcheck", function() structure(list(goodpractice = gp_failure), class = "pkgcheck"))
stopifnot(identical(gp_receipt$pass, FALSE), identical(pkg_receipt$pass, FALSE))
cat("Nested failure receipts preserved\n")
