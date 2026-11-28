evaluate_readiness <- function(
  current_evidence,
  quality,
  export_docs,
  workflow_documented,
  headline_results,
  issue_queries,
  ci_configured,
  ci_runs
) {
  current_commit <- current_evidence$commit
  current_tree_clean <- current_evidence$working_tree_clean
  quality_by_step <- merge_quality_evidence(quality, current_commit)
  record <- function(criterion, status, evidence) data.frame(criterion, status, evidence, stringsAsFactors = FALSE)
  check_pass <- function(name) {
    item <- quality_by_step[[quality_receipt_ids[[name]]]]
    !is.null(item) &&
      identical(item$status, "completed") &&
      identical(item$pass, TRUE) &&
      quality_evidence_valid(item, current_commit, current_tree_clean)
  }
  coverage <- quality_by_step[[quality_receipt_ids[["coverage_percent"]]]]
  coverage_value <- if (quality_evidence_valid(coverage, current_commit, current_tree_clean)) {
    coverage_percent_value(coverage)
  } else {
    NA_real_
  }
  exports <- export_docs$exports
  man_examples <- export_docs$has_examples
  issues_clean <- length(issue_queries) == 2L &&
    all(vapply(issue_queries, `[[`, logical(1), "ok")) &&
    all(vapply(issue_queries, `[[`, integer(1), "count") == 0L)
  ci_runs_ok <- current_tree_clean &&
    valid_nonempty_string(current_commit) &&
    ci_configured &&
    ci_runs_succeeded(ci_runs, current_commit)
  pkgcheck <- quality_by_step[[quality_receipt_ids[["pkgcheck"]]]]
  manual_pass <- check_pass("guide")
  pkgcheck_available <- !is.null(pkgcheck) && !identical(pkgcheck$status, "skipped_not_installed")
  pkgcheck_pass <- pkgcheck_available && check_pass("pkgcheck") && manual_pass
  coverage_ready <- is.finite(coverage_value) &&
    coverage_value >= quality_coverage_minimum &&
    check_pass("coverage_percent")
  pkgdown_ready <- check_pass("pkgdown") && workflow_documented
  ci_status <- if (ci_runs_ok) "ready" else "not verified"
  as_cran_evidence <- function() {
    if (!ci_configured) {
      return("No CI workflow runs --as-cran")
    }
    if (!current_tree_clean) {
      return("Working tree is dirty")
    }
    if (!valid_nonempty_string(current_commit)) {
      return("Could not identify HEAD")
    }
    if (inherits(ci_runs, "error") || !is.null(attr(ci_runs, "status", exact = TRUE))) {
      return("Unable to query CI run status")
    }
    if (ci_runs_ok) {
      return(paste("R-CMD-check succeeded on", current_commit))
    }
    paste("No successful R-CMD-check run found for", current_commit)
  }
  rbind(
    record("R CMD check --as-cran: 0/0/0 on CI", ci_status, as_cran_evidence()),
    record(
      "rOpenSci packaging-guide conformance",
      if (pkgcheck_pass) {
        "ready"
      } else if (!pkgcheck_available) {
        "not verified"
      } else {
        "not met"
      },
      if (!pkgcheck_available) {
        "pkgcheck is unavailable; manual checklist alone cannot establish conformance"
      } else {
        "Requires pkgcheck to pass except the listed roadmap exceptions, and a passing manual subset, on the clean current commit"
      }
    ),
    record(
      sprintf("Test coverage >= %s%%", quality_coverage_minimum),
      if (coverage_ready) {
        "ready"
      } else if (!is.finite(coverage_value)) {
        "not measured"
      } else {
        "not met"
      },
      if (!is.finite(coverage_value)) {
        "No measured covr result from a clean checkout of HEAD"
      } else {
        paste("Latest covr percentage:", coverage_value, "on commit", current_commit)
      }
    ),
    record(
      "Every export has runnable examples",
      if (length(exports) && all(man_examples)) ci_status else "not met",
      paste(
        sum(man_examples),
        "of",
        length(exports),
        "exports have examples.",
        as_cran_evidence()
      )
    ),
    record(
      "pkgdown documents the full workflow",
      if (pkgdown_ready) "ready" else "not met",
      paste(
        "pkgdown check on current commit:",
        check_pass("pkgdown"),
        "; full workflow topics documented:",
        workflow_documented
      )
    ),
    record(
      "Cyclomatic complexity <= 15 per function",
      if (check_pass("namespace_complexity")) "ready" else "not met",
      "Requires a passing installed-namespace cyclocomp result for the current commit"
    ),
    record(
      "Reproduces headline estimates of 3 published NIS studies within stated tolerance",
      if (is.null(headline_results)) {
        "not verified"
      } else if (all(headline_results$status == "pass")) {
        "ready"
      } else {
        "not met"
      },
      study_verification_summary(headline_results)
    ),
    record(
      "No open P0/P1 issues",
      if (issues_clean) "ready" else "not met",
      "GitHub open issue query using P0 and P1 labels"
    )
  )
}
