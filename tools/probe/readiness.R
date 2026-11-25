root <- normalizePath(".", mustWork = TRUE)
source(file.path("tools", "probe", "probe-modules.R"))
source(file.path("tools", "probe", "readiness-ci.R"))
source(file.path("tools", "probe", "quality-checks.R"))
source(file.path("tools", "probe", "readiness-criteria.R"))
loop_dir <- probe_workspace(root)
quality_files <- list.files(loop_dir, pattern = "^quality[.]jsonl$", recursive = TRUE, full.names = TRUE)
quality_files <- quality_files[order(file.info(quality_files)$mtime)]
quality <- load_quality_evidence(quality_files)
current_evidence <- git_evidence()
current_commit <- current_evidence$commit
current_tree_clean <- current_evidence$working_tree_clean
ci_files <- list.files(".github/workflows", pattern = "[.]ya?ml$", full.names = TRUE)
ci_text <- paste(unlist(lapply(ci_files, readLines, warn = FALSE)), collapse = "\n")
reference_studies <- load_reference_studies(file.path(root, "tools", "probe", "reference-studies.yml"))
headline_pass <- current_tree_clean && valid_reference_studies(reference_studies) &&
  all(vapply(reference_studies, function(study) {
    receipt <- file.path(loop_dir, "private", "study-verification", paste0(study$id, ".json"))
    study_verification_ready(receipt, current_commit, study)
  }, logical(1)))
query_open_issues <- function(label) {
  result <- tryCatch(system2("gh", c("issue", "list", "--state", "open",
    "--label", label, "--json", "number"), stdout = TRUE, stderr = FALSE),
    error = identity)
  if (inherits(result, "error")) return(list(ok = FALSE, count = NA_integer_))
  query_status <- attr(result, "status", exact = TRUE)
  parse_open_issue_query(result, status = if (is.null(query_status)) 0L else query_status)
}
issue_queries <- lapply(c("P0", "P1"), query_open_issues)
ci_configured <- grepl("--as-cran", ci_text, fixed = TRUE)
ci_runs <- if (ci_configured) tryCatch(system2("gh", ci_run_list_args(current_commit),
  stdout = TRUE, stderr = FALSE), error = identity) else character()
doc_files <- c("README.md", list.files("vignettes", pattern = "[.](Rmd|qmd|md)$",
  recursive = TRUE, full.names = TRUE))
doc_text <- paste(unlist(lapply(doc_files[file.exists(doc_files)], readLines, warn = FALSE)), collapse = "\n")
workflow_topics <- c("nis_open", "nis_flag_dx", "nis_design", "survey_mean", "svyglm",
  "nis_suppress", "nis_cost")
workflow_documented <- length(workflow_topics) > 0L &&
  all(vapply(workflow_topics, grepl, logical(1), x = doc_text, fixed = TRUE))
criteria <- evaluate_readiness(current_evidence, quality, exported_example_status(root),
  workflow_documented, headline_pass, issue_queries, ci_configured, ci_runs)
print(criteria, row.names = FALSE)
