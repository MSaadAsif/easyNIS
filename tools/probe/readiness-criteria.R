evaluate_readiness <- function(current_evidence, quality, export_docs, workflow_documented,
                               headline_pass, issue_queries, ci_configured, ci_runs) {
  current_commit <- current_evidence$commit
  current_tree_clean <- current_evidence$working_tree_clean
  quality_by_step <- merge_quality_evidence(quality, current_commit)
  record <- function(criterion, status, evidence) data.frame(criterion, status, evidence, stringsAsFactors = FALSE)
  check_pass <- function(name) {
    item <- quality_by_step[[quality_receipt_ids[[name]]]]
    !is.null(item) && identical(item$status, "completed") &&
      identical(item$pass, TRUE) && quality_evidence_valid(item, current_commit, current_tree_clean)
  }
  coverage <- quality_by_step[[quality_receipt_ids[["coverage_percent"]]]]
  coverage_value <- if (is.null(coverage)) NA_real_ else coverage_percent_value(coverage)
  exports <- export_docs$exports
  man_examples <- export_docs$has_examples
  issues_clean <- length(issue_queries) == 2L &&
    all(vapply(issue_queries, `[[`, logical(1), "ok")) &&
    all(vapply(issue_queries, `[[`, integer(1), "count") == 0L)
  ci_runs_ok <- ci_configured && ci_runs_succeeded(ci_runs, current_commit)
  pkgcheck <- quality_by_step[[quality_receipt_ids[["pkgcheck"]]]]
  manual_pass <- check_pass("guide")
  pkgcheck_available <- !is.null(pkgcheck) && !identical(pkgcheck$status, "skipped_not_installed")
  pkgcheck_pass <- pkgcheck_available && check_pass("pkgcheck") && manual_pass
  coverage_ready <- is.finite(coverage_value) && coverage_value >= 90 &&
    check_pass("coverage_percent")
  examples_ready <- all(man_examples) && check_pass("as_cran")
  pkgdown_ready <- check_pass("pkgdown") && workflow_documented
  local_as_cran_ready <- check_pass("as_cran")
  as_cran_status <- function(ci_pass, local_pass) {
    if (ci_pass && local_pass) return("ready")
    "not met"
  }
  as_cran_evidence <- function() {
    if (!ci_configured) return("No CI workflow runs --as-cran")
    if (!current_tree_clean) return("Working tree is dirty; clean evidence is required")
    if (inherits(ci_runs, "error")) return("Unable to query CI run status")
    paste("Requires successful CI and local zero-error/warning/note evidence for", current_commit)
  }
  rbind(
    record("R CMD check --as-cran: 0/0/0 on CI", as_cran_status(ci_runs_ok, local_as_cran_ready), as_cran_evidence()),
    record("rOpenSci packaging-guide conformance", if (pkgcheck_pass) "ready" else if (!pkgcheck_available) "not verified" else "not met", if (!pkgcheck_available) "pkgcheck is unavailable; manual checklist alone cannot establish conformance" else "Requires passing pkgcheck and the passing manual subset from a clean current commit"),
    record("Test coverage >= 90%", if (coverage_ready) "ready" else if (!is.finite(coverage_value)) "not measured" else "not met", if (!is.finite(coverage_value)) "Latest covr run unavailable" else paste("Latest covr percentage:", coverage_value, "on commit", if (identical(coverage$commit, current_commit)) current_commit else "unknown")),
    record("Every export has runnable examples", if (examples_ready) "ready" else "not met", paste(sum(man_examples), "of", length(exports), "exports have examples; a clean current-commit package check is required")),
    record("pkgdown documents the full workflow", if (pkgdown_ready) "ready" else "not met", paste("pkgdown check on current commit:", check_pass("pkgdown"), "; full workflow topics documented:", workflow_documented)),
    record("Cyclomatic complexity <= 15 per function", if (check_pass("cyclocomp")) "ready" else "not met", "Requires a passing cyclocomp_linter(15) result for the current commit"),
    record("Reproduces headline estimates of 3 published NIS studies within stated tolerance", if (headline_pass) "ready" else "not verified", "Requires three listed studies and passing local receipts matched to HEAD; only pass/fail is printed"),
    record("No open P0/P1 issues", if (issues_clean) "ready" else "not met", "GitHub open issue query using P0 and P1 labels")
  )
}
