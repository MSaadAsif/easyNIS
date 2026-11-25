source(file.path("tools", "probe", "readiness-ci.R"))

synthetic_commit <- "synthetic-commit"
main_run <- list(
  name = "R-CMD-check",
  status = "completed",
  conclusion = "success",
  headSha = synthetic_commit
)
synthetic_response <- jsonlite::toJSON(list(main_run), auto_unbox = TRUE)

stopifnot(ci_runs_succeeded(synthetic_response, synthetic_commit),
  !ci_runs_succeeded(synthetic_response, "different-commit"))

for (field in c("name", "status", "conclusion", "headSha")) {
  altered_run <- main_run
  altered_run[[field]] <- switch(field,
    name = "Lint",
    status = "in_progress",
    conclusion = "failure",
    headSha = "different-commit")
  altered_response <- jsonlite::toJSON(list(altered_run), auto_unbox = TRUE)
  stopifnot(!ci_runs_succeeded(altered_response, synthetic_commit))
}

similar_workflow <- main_run
similar_workflow$name <- "backup R-CMD-check"
stopifnot(!ci_runs_succeeded(jsonlite::toJSON(list(similar_workflow), auto_unbox = TRUE),
  synthetic_commit))

suffix_only <- stats::setNames(main_run, paste0(names(main_run), "_other"))
duplicate <- '{"name":"R-CMD-check","headSha":"synthetic-commit","status":"completed","conclusion":"success","conclusion":"failure"}'
stopifnot(!ci_runs_succeeded(jsonlite::toJSON(list(suffix_only), auto_unbox = TRUE), synthetic_commit),
  !ci_runs_succeeded(paste0("[", duplicate, "]"), synthetic_commit))

failed_response <- structure(synthetic_response, status = 1L)
stopifnot(!ci_runs_succeeded(failed_response, synthetic_commit),
  !ci_runs_succeeded("{malformed", synthetic_commit),
  !ci_runs_succeeded('{"name":"R-CMD-check"}', synthetic_commit))

cat("Readiness CI tests passed.\n")
