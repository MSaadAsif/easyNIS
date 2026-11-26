quality_check <- function(name, provenance, run, pass = NULL, detail = NULL, redact_detail = TRUE) {
  list(name = name, provenance = provenance, run = run, pass = pass, detail = detail, redact_detail = redact_detail)
}

lint_check <- function(name, run) {
  quality_check(
    name,
    "source_inspection",
    run,
    pass = function(x) x$pass && length(x$value) == 0L,
    detail = function(x, passed) lint_detail(x$value),
    redact_detail = FALSE
  )
}

nested_check <- function(name, run, pass) {
  quality_check(name, "nested_unverified", run, pass = function(x) pass(x$value), detail = function(x, passed) {
    quality_public_detail(name, passed)
  })
}

quality_checks <- list(
  as_cran = quality_check("R CMD check --as-cran", "nested_unverified", function(root) {
    devtools::check(root, document = FALSE, args = c("--as-cran", "--no-manual"), error_on = "never")
  }),
  lintr = lint_check("lintr", function(root) lintr::lint_package(root)),
  cyclocomp = lint_check("cyclocomp_linter(15)", function(root) {
    lintr::lint_package(root, linters = list(cyclocomp = lintr::cyclocomp_linter(15)))
  }),
  namespace_complexity = quality_check(
    "installed_namespace_complexity",
    "isolated_namespace_verified",
    function(root) {
      with_verified_source(root, function(root, package) cyclocomp::cyclocomp_package(package))
    },
    pass = function(x) namespace_complexity_pass(x$value)
  ),
  coverage = quality_check(
    "covr",
    "nested_unverified",
    function(root) {
      covr::package_coverage(root, quiet = TRUE)
    },
    pass = function(x) {
      inherits(x$value, "coverage") &&
        x$pass &&
        covr::percent_coverage(x$value) >= 90
    }
  ),
  goodpractice = nested_check(
    "goodpractice",
    function(root) {
      if (!requireNamespace("goodpractice", quietly = TRUE)) {
        return("not installed")
      }
      with_verified_source(root, function(root, package) goodpractice::gp(root))
    },
    function(value) goodpractice_pass(value)
  ),
  pkgcheck = nested_check(
    "pkgcheck",
    function(root) {
      if (!requireNamespace("pkgcheck", quietly = TRUE)) {
        return("not installed")
      }
      with_verified_source(root, function(root, package) pkgcheck::pkgcheck(root))
    },
    function(value) pkgcheck_pass(value)
  ),
  pkgdown = quality_check("pkgdown::check_pkgdown", "source_inspection", function(root) {
    if (!requireNamespace("pkgdown", quietly = TRUE)) {
      return("not installed")
    }
    pkgdown::check_pkgdown(root)
  })
)

quality_receipt_ids <- c(
  vapply(quality_checks, "[[", character(1), "name"),
  export_arguments = "export_arguments",
  export_documentation = "export_documentation",
  guide = "ropensci_manual_subset",
  coverage_percent = "coverage_percent"
)

quality_definition <- function(name) {
  key <- names(quality_receipt_ids)[match(name, quality_receipt_ids)]
  if (is.na(key)) {
    stop("Unknown quality check.", call. = FALSE)
  }
  if (key == "export_arguments") {
    return(quality_check(name, "isolated_namespace_verified", NULL))
  }
  quality_checks[[key]]
}

run_quality_checks <- function(root, requested) {
  unknown <- setdiff(requested, names(quality_checks))
  if (length(unknown)) {
    stop("Unknown EASYNIS_QUALITY_STEPS: ", paste(unknown, collapse = ", "))
  }
  checks <- lapply(names(quality_checks), function(key) {
    check <- quality_checks[[key]]
    if (length(requested) && !key %in% requested) {
      return(list(
        name = check$name,
        pass = NA,
        error_class = "",
        error = "",
        warnings = "",
        elapsed_seconds = 0,
        value = "skipped_by_selection"
      ))
    }
    capture_quality_step(check$name, function() check$run(root))
  })
  stats::setNames(checks, names(quality_checks))
}
