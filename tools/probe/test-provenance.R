source("tools/probe/provenance.R")
source("tools/probe/quality-checks.R")
source("tools/probe/probe-modules.R")
local({
  scratch <- tempfile("quality-fixture-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  make_package <- function(path, definition) {
    dir.create(file.path(path, "R"), recursive = TRUE)
    writeLines(
      c(
        "Package: qualityprovenancefixture",
        "Version: 0.0.1",
        "Title: Invented Fixture",
        "Description: An invented test fixture.",
        "License: MIT",
        "Author: Fixture Author",
        "Maintainer: Fixture Author <fixture@example.org>"
      ),
      file.path(path, "DESCRIPTION")
    )
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
  make_package(broken, "marker <- function( {")
  callr::rcmd("INSTALL", c(paste0("--library=", library), older), fail_on_status = TRUE)
  previous <- .libPaths()
  on.exit(.libPaths(previous), add = TRUE)
  .libPaths(c(library, previous))
  pkgload::load_all(requested, quiet = TRUE)
  on.exit(pkgload::unload("qualityprovenancefixture"), add = TRUE)
  # An older installation with the same version remains available on failure.
  failed <- tryCatch(
    with_verified_source(broken, function(root, package) {
      stop("Callback must never run after failed installation")
    }),
    error = identity
  )
  stopifnot(inherits(failed, "error"), !grepl("Callback must never", conditionMessage(failed)))
  cat("Install failure refused before callback\n")
  for (throws in c(FALSE, TRUE)) {
    captured <- capture_quality_step("invented", function() {
      with_verified_source(requested, function(root, package) {
        warning(structure(
          list(message = "INVENTED_WARNING", call = NULL),
          class = c("invented_warning", "warning", "condition")
        ))
        if (throws) {
          stop("Invented callback failure")
        }
        FALSE
      })
    })
    stopifnot(
      length(captured$warning_conditions) == 1L,
      inherits(captured$warning_conditions[[1L]], "invented_warning"),
      identical(conditionMessage(captured$warning_conditions[[1L]]), "INVENTED_WARNING"),
      identical(inherits(captured$value, "error"), throws)
    )
  }
  result <- with_verified_source(requested, function(root, package) {
    list(
      marker = getExportedValue(package, "marker")(),
      complexity = cyclocomp::cyclocomp_package(package)$cyclocomp,
      version = as.character(utils::packageVersion(package))
    )
  })
  stopifnot(identical(result$marker, "requested"), result$complexity == 2, result$version == "0.0.1")
  cat("Loaded parent / same-version fallback: isolated requested namespace measured\n")
})
source("tools/probe/quality-result.R")
evidence <- list(commit = "invented", working_tree_clean = TRUE)
synthetic_hits <- c(1, 0)
synthetic_coverage <- structure(list(hits = synthetic_hits), class = "coverage")
coverage_record <- coverage_percent_record(
  list(value = synthetic_coverage, error_class = ""),
  evidence,
  percent_coverage = function(value) 100 * mean(value$hits > 0)
)
stopifnot(
  identical(coverage_record$status, "completed"),
  identical(coverage_record$pass, FALSE),
  identical(coverage_record$value, 50)
)
passing_coverage <- structure(list(hits = c(1, 1)), class = "coverage")
passing_coverage_record <- coverage_percent_record(
  list(value = passing_coverage, error_class = ""),
  evidence,
  percent_coverage = function(value) 100 * mean(value$hits > 0)
)
stopifnot(
  identical(passing_coverage_record$status, "completed"),
  isTRUE(passing_coverage_record$pass),
  identical(passing_coverage_record$value, 100),
  identical(passing_coverage_record$commit, evidence$commit),
  isTRUE(passing_coverage_record$working_tree_clean)
)
stopifnot(is.null(coverage_percent_record(
  list(value = "skipped_by_selection"),
  evidence,
  percent_coverage = identity
)))
failed_coverage_record <- coverage_percent_record(
  list(value = simpleError("invented failure"), error_class = "simpleError"),
  evidence,
  percent_coverage = identity
)
stopifnot(
  identical(failed_coverage_record$status, "failed"),
  identical(failed_coverage_record$pass, FALSE),
  is.na(failed_coverage_record$value),
  identical(failed_coverage_record$error_class, "simpleError")
)
receipt <- function(name, fn) quality_record(capture_quality_step(name, fn), evidence)
check <- receipt("R CMD check --as-cran", function() {
  list(errors = character(), warnings = character(), notes = character())
})
stopifnot(isTRUE(check$pass), check$status == "completed")
failed <- receipt("R CMD check --as-cran", function() {
  list(errors = "invented failure", warnings = character(), notes = character())
})
stopifnot(identical(failed$pass, FALSE))
failed_install <- receipt("installed_namespace_complexity", function() stop("invented failure"))
stopifnot(
  identical(failed_install$pass, FALSE),
  failed_install$status == "failed"
)
measured <- receipt("installed_namespace_complexity", function() data.frame(name = "marker", cyclocomp = 2))
stopifnot(isTRUE(measured$pass), measured$status == "completed")
unknown <- receipt("pkgcheck", function() structure(list(), class = "pkgcheck"))
stopifnot(is.na(unknown$pass), unknown$status == "not_verified")
cat("Production receipt provenance tests passed\n")
stopifnot(
  is.na(namespace_complexity_pass(NULL)),
  is.na(namespace_complexity_pass(data.frame(cyclocomp = numeric()))),
  is.na(namespace_complexity_pass(data.frame(cyclocomp = NA_real_))),
  identical(namespace_complexity_pass(data.frame(cyclocomp = 16)), FALSE)
)
skipped <- receipt("installed_namespace_complexity", function() "skipped_by_selection")
stopifnot(is.na(skipped$pass), skipped$status == "skipped_by_selection")
gp_failure <- structure(list(checks = list(invented = list(status = FALSE))), class = "goodPractice")
gp_receipt <- receipt("goodpractice", function() gp_failure)
pkg_receipt <- receipt("pkgcheck", function() structure(list(goodpractice = gp_failure), class = "pkgcheck"))
stopifnot(identical(gp_receipt$pass, FALSE), identical(pkg_receipt$pass, FALSE))
cat("Nested failure receipts preserved\n")

local({
  path <- tempfile(fileext = ".R")
  on.exit(unlink(path))
  writeLines(
    c(
      'print.fixture <- function(x, ...) { cat("allowed"); invisible(x) }',
      'announce <- function(x) { base::print(x); "cat() is text" }'
    ),
    path
  )
  stopifnot(identical(guide_console_calls(path, "S3method(print,fixture)"), paste0(path, ":2")))

  position <- list(filename = "R/convert-encoding.R", line = "nis_convert_sas_encoding (59 lines)")
  stopifnot(
    pkgcheck_positions_allowed("complexity_function_length", list(position)),
    !pkgcheck_positions_allowed("complexity_function_length", list()),
    !pkgcheck_positions_allowed(
      "complexity_function_length",
      list(
        position,
        list(
          filename = "R/convert-encoding.R",
          line = "unreviewed_function (59 lines)"
        )
      )
    ),
    !pkgcheck_positions_allowed("unreviewed_check", list(position))
  )
})
