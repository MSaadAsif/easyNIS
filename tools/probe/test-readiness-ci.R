source(file.path("tools", "probe", "readiness-ci.R"))

synthetic_commit <- "synthetic-commit"
main_run <- list(
  name = "R-CMD-check",
  status = "completed",
  conclusion = "success",
  headSha = synthetic_commit
)
synthetic_response <- jsonlite::toJSON(list(main_run), auto_unbox = TRUE)

stopifnot(identical(ci_run_list_args(commit = synthetic_commit),
  c("run", "list", "--commit", synthetic_commit,
    "--json", "name,status,conclusion,headSha", "--limit", "100")),
  ci_runs_succeeded(synthetic_response, synthetic_commit),
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

failed_response <- structure(synthetic_response, status = 1L)
stopifnot(!ci_runs_succeeded(failed_response, synthetic_commit),
  !ci_runs_succeeded("{malformed", synthetic_commit),
  !ci_runs_succeeded('{"name":"R-CMD-check"}', synthetic_commit))

cat("Readiness CI tests passed.\n")
