root <- normalizePath(".", mustWork = TRUE)
source(file.path("tools", "probe", "helpers.R"))
main_repo <- find_main_repo(root)
read_main_renviron(main_repo)
loop_dir <- Sys.getenv("EASYNIS_LOOP_DIR", unset = file.path(main_repo, "local", "loop"))
quality_files <- list.files(loop_dir, pattern = "^quality[.]jsonl$", recursive = TRUE, full.names = TRUE)
quality_files <- quality_files[order(file.info(quality_files)$mtime)]
quality <- if (!length(quality_files) || !requireNamespace("jsonlite", quietly = TRUE)) list() else
  unlist(lapply(quality_files, function(file) lapply(readLines(file, warn = FALSE),
    jsonlite::fromJSON, simplifyVector = FALSE)), recursive = FALSE)
current_evidence <- git_evidence()
current_commit <- current_evidence$commit
current_tree_clean <- current_evidence$working_tree_clean
quality_by_step <- list()
for (item in quality) {
  if (!identical(item$status, "skipped_by_selection") &&
      quality_evidence_valid(item, current_commit, current_tree_clean)) {
    quality_by_step[[item$step]] <- item
  }
}
record <- function(criterion, status, evidence) data.frame(criterion, status, evidence, stringsAsFactors = FALSE)
check_pass <- function(name) {
  item <- quality_by_step[[name]]
  !is.null(item) && identical(item$status, "completed") &&
    identical(item$pass, TRUE) && quality_evidence_valid(item, current_commit, current_tree_clean)
}
coverage <- quality_by_step[["coverage_percent"]]
coverage_value <- if (is.null(coverage)) NA_real_ else coverage_percent_value(coverage)
export_docs <- exported_example_status(root)
exports <- export_docs$exports
man_examples <- export_docs$has_examples
ci_files <- list.files(".github/workflows", pattern = "[.]ya?ml$", full.names = TRUE)
ci_text <- paste(unlist(lapply(ci_files, readLines, warn = FALSE)), collapse = "\n")
study_receipts <- list.files(loop_dir, pattern = "^study-verification[.]json$",
  recursive = TRUE, full.names = TRUE)
study_receipts <- study_receipts[grepl("[/\\\\]private[/\\\\]", study_receipts)]
headline_pass <- current_tree_clean && length(study_receipts) > 0L &&
  any(vapply(study_receipts, study_verification_ready, logical(1), current_commit = current_commit))
query_open_issues <- function(label) {
  result <- tryCatch(system2("gh", c("issue", "list", "--state", "open",
    "--label", label, "--json", "number"), stdout = TRUE, stderr = FALSE),
    error = identity)
  if (inherits(result, "error")) return(list(ok = FALSE, count = NA_integer_))
  query_status <- attr(result, "status", exact = TRUE)
  parse_open_issue_query(result, status = if (is.null(query_status)) 0L else query_status)
}
issue_queries <- lapply(c("P0", "P1"), query_open_issues)
issues_clean <- length(issue_queries) == 2L &&
  all(vapply(issue_queries, `[[`, logical(1), "ok")) &&
  all(vapply(issue_queries, `[[`, integer(1), "count") == 0L)
current_branch <- tryCatch(system2("git", c("branch", "--show-current"),
  stdout = TRUE, stderr = FALSE)[[1L]], error = function(e) "")
ci_configured <- grepl("--as-cran", ci_text, fixed = TRUE)
ci_runs <- if (ci_configured) tryCatch(system2("gh", c("run", "list", "--branch",
  current_branch, "--json", "name,status,conclusion,headSha", "--limit", "100"),
  stdout = TRUE, stderr = FALSE), error = identity) else character()
ci_run_succeeded <- function(run, commit) {
  grepl("R-CMD-check", run$name, ignore.case = TRUE) &&
    identical(run$headSha, commit) && identical(run$status, "completed") &&
    identical(run$conclusion, "success")
}
ci_runs_ok <- FALSE
if (ci_configured && !inherits(ci_runs, "error") &&
    (!length(attr(ci_runs, "status")) || attr(ci_runs, "status") == 0L)) {
  parsed_runs <- tryCatch(jsonlite::fromJSON(paste(ci_runs, collapse = "\n"),
    simplifyVector = FALSE), error = function(e) NULL)
  if (is.list(parsed_runs)) {
    ci_runs_ok <- any(vapply(parsed_runs, ci_run_succeeded, logical(1), commit = current_commit))
  }
}
doc_files <- c("README.md", list.files("vignettes", pattern = "[.](Rmd|qmd|md)$",
  recursive = TRUE, full.names = TRUE))
doc_text <- paste(unlist(lapply(doc_files[file.exists(doc_files)], readLines, warn = FALSE)), collapse = "\n")
workflow_topics <- c("nis_open", "nis_flag_dx", "nis_design", "survey_mean", "svyglm",
  "nis_suppress", "nis_cost")
workflow_documented <- length(workflow_topics) > 0L &&
  all(vapply(workflow_topics, grepl, logical(1), x = doc_text, fixed = TRUE))
manual <- quality_by_step[["ropensci_manual_subset"]]
pkgcheck <- quality_by_step[["pkgcheck"]]
manual_pass <- !is.null(manual) && identical(manual$pass, TRUE) &&
  identical(manual$commit, current_commit)
pkgcheck_available <- !is.null(pkgcheck) && !identical(pkgcheck$status, "skipped_not_installed")
pkgcheck_pass <- pkgcheck_available && check_pass("pkgcheck") && manual_pass
coverage_ready <- is.finite(coverage_value) && coverage_value >= 90 &&
  quality_evidence_valid(coverage, current_commit, current_tree_clean) &&
  identical(coverage$pass, TRUE)
examples_ready <- all(man_examples) && check_pass("R CMD check --as-cran")
pkgdown_ready <- check_pass("pkgdown::check_pkgdown") && workflow_documented
local_as_cran_ready <- check_pass("R CMD check --as-cran")
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
criteria <- rbind(
  record("R CMD check --as-cran: 0/0/0 on CI", as_cran_status(ci_runs_ok, local_as_cran_ready), as_cran_evidence()),
  record("rOpenSci packaging-guide conformance", if (pkgcheck_pass) "ready" else if (!pkgcheck_available) "not verified" else "not met", if (!pkgcheck_available) "pkgcheck is unavailable; manual checklist alone cannot establish conformance" else "Requires passing pkgcheck and the passing manual subset from a clean current commit"),
  record("Test coverage >= 90%", if (coverage_ready) "ready" else if (!is.finite(coverage_value)) "not measured" else "not met", if (!is.finite(coverage_value)) "Latest covr run unavailable" else paste("Latest covr percentage:", coverage_value, "on commit", if (is.null(coverage$commit)) "unknown" else coverage$commit)),
  record("Every export has runnable examples", if (examples_ready) "ready" else "not met", paste(sum(man_examples), "of", length(exports), "exports have examples; a clean current-commit package check is required")),
  record("pkgdown documents the full workflow", if (pkgdown_ready) "ready" else "not met", paste("pkgdown check on current commit:", check_pass("pkgdown::check_pkgdown"), "; full workflow topics documented:", workflow_documented)),
  record("Cyclomatic complexity <= 15 per function", if (check_pass("cyclocomp_linter(15)")) "ready" else "not met", "Requires a passing cyclocomp_linter(15) result for the current commit"),
  record("Reproduces headline estimates of 3 published NIS studies within stated tolerance", if (headline_pass) "ready" else "not verified", "A local-only receipt tied to the current commit and a verification timestamp is required; never publish estimates"),
  record("No open P0/P1 issues", if (issues_clean) "ready" else "not met", "GitHub open issue query using P0 and P1 labels")
)
print(criteria, row.names = FALSE)
