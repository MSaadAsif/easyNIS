ci_run_list_args <- function(commit) {
  c(
    "run",
    "list",
    "--workflow",
    "R-CMD-check.yaml",
    "--commit",
    commit,
    "--json",
    "name,event,status,conclusion,headSha",
    "--limit",
    "100"
  )
}

ci_run_succeeded <- function(run, commit) {
  fields <- c("name", "event", "headSha", "status", "conclusion")
  # On pull_request, actions/checkout uses the merge ref, even if headSha matches.
  is.list(run) &&
    !anyDuplicated(names(run)) &&
    all(fields %in% names(run)) &&
    identical(run$name, "R-CMD-check") &&
    is.character(run$event) &&
    length(run$event) == 1L &&
    run$event %in% c("push", "schedule", "workflow_dispatch") &&
    identical(run$headSha, commit) &&
    identical(run$status, "completed") &&
    identical(run$conclusion, "success")
}

ci_runs_succeeded <- function(output, commit) {
  status <- attr(output, "status", exact = TRUE)
  if (!is.null(status) && !identical(status, 0L)) {
    return(FALSE)
  }
  if (!is.character(output)) {
    return(FALSE)
  }

  runs <- tryCatch(jsonlite::fromJSON(paste(output, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(runs) || (length(runs) && !is.null(names(runs)))) {
    return(FALSE)
  }
  any(vapply(runs, ci_run_succeeded, logical(1), commit = commit))
}
