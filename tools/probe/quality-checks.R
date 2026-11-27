quality_check <- function(name, run, pass = NULL, detail = NULL) {
  list(name = name, run = run, pass = pass, detail = detail)
}

diagnostic_check <- function(name, run, pass) {
  quality_check(name, run, pass = function(x) pass(x$value), detail = function(x, passed) {
    quality_public_detail(name, passed)
  })
}

quality_checks <- list(
  as_cran = quality_check("R CMD check --as-cran", function(root) {
    devtools::check(root, document = FALSE, args = c("--as-cran", "--no-manual"), error_on = "never")
  }),
  namespace_complexity = quality_check(
    "installed_namespace_complexity",
    function(root) namespace_complexity(root),
    pass = function(x) namespace_complexity_pass(x$value)
  ),
  coverage = quality_check(
    "covr",
    function(root) {
      covr::package_coverage(root, quiet = TRUE)
    },
    pass = function(x) {
      inherits(x$value, "coverage") &&
        x$pass &&
        covr::percent_coverage(x$value) >= 90
    }
  ),
  goodpractice = diagnostic_check(
    "goodpractice",
    function(root) {
      if (!requireNamespace("goodpractice", quietly = TRUE)) {
        return("not installed")
      }
      covered <- goodpractice::checks_by_group(c("lintr", "tidyverse", "cyclocomp"))
      checks <- setdiff(goodpractice::default_checks(), covered)
      goodpractice::gp(root, checks = checks)
    },
    function(value) goodpractice_pass(value)
  ),
  pkgcheck = diagnostic_check(
    "pkgcheck",
    function(root) {
      if (!requireNamespace("pkgcheck", quietly = TRUE)) {
        return("not installed")
      }
      pkgcheck::pkgcheck(root, goodpractice = FALSE, use_cache = FALSE)
    },
    function(value) pkgcheck_pass(value)
  ),
  pkgdown = quality_check("pkgdown::check_pkgdown", function(root) {
    if (!requireNamespace("pkgdown", quietly = TRUE)) {
      return("not installed")
    }
    pkgdown::check_pkgdown(root)
  })
)

guide_console_calls <- function(path, namespace) {
  code <- parse(path, keep.source = TRUE)
  tokens <- utils::getParseData(code)
  lines <- tokens$line1[tokens$token == "SYMBOL_FUNCTION_CALL" & tokens$text %in% c("print", "cat")]
  methods <- grep("^S3method\\((print|str),[^,]+\\)$", namespace, value = TRUE)
  methods <- chartr(",", ".", sub("^S3method\\((.*)\\)$", "\\1", methods))
  for (i in seq_along(code)) {
    definition <- code[[i]]
    if (
      is.call(definition) &&
        identical(definition[[1L]], quote(`<-`)) &&
        is.symbol(definition[[2L]]) &&
        as.character(definition[[2L]]) %in% methods &&
        is.call(definition[[3L]]) &&
        identical(definition[[3L]][[1L]], quote(`function`))
    ) {
      span <- attr(code, "srcref")[[i]]
      lines <- lines[lines < span[1L] | lines > span[3L]]
    }
  }
  if (length(lines)) paste0(path, ":", lines) else character()
}

guide_first_argument_exceptions <- c(
  nis_attrition_cohort = "flow",
  nis_ccsr_codes = "categories",
  nis_example = "years",
  nis_vars_demographics = "",
  nis_vars_design = "",
  nis_vars_dx = "",
  nis_vars_hospital = "",
  nis_vars_pr = ""
)

guide_data_first <- function(exported_args) {
  first <- vapply(exported_args, function(args) if (length(args)) args[[1L]] else "", character(1))
  exceptions <- guide_first_argument_exceptions[names(first)]
  allowed <- !is.na(exceptions) & first == exceptions
  names(first)[!(first %in% c(".data", "data", "x", "design", "path", "file") | allowed)]
}

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
    return(quality_check(name, NULL))
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
