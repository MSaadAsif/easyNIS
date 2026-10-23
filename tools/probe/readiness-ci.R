ci_run_list_args <- function(commit) {
  c("run", "list", "--commit", commit,
    "--json", "name,status,conclusion,headSha", "--limit", "100")
}

ci_run_succeeded <- function(run, commit) {
  is.list(run) && is.character(run$name) && length(run$name) == 1L &&
    !is.na(run$name) && grepl("R-CMD-check", run$name, ignore.case = TRUE) &&
    identical(run$headSha, commit) && identical(run$status, "completed") &&
    identical(run$conclusion, "success")
}

ci_runs_succeeded <- function(output, commit) {
  status <- attr(output, "status", exact = TRUE)
  if (!is.null(status) && !identical(status, 0L)) return(FALSE)
  if (!is.character(output)) return(FALSE)

  runs <- tryCatch(jsonlite::fromJSON(paste(output, collapse = "\n"),
    simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(runs) || (length(runs) && !is.null(names(runs)))) return(FALSE)
  any(vapply(runs, ci_run_succeeded, logical(1), commit = commit))
}
