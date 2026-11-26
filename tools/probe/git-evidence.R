git_evidence <- function() {
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) {
    character()
  })
  status <- tryCatch(
    system2("git", c("status", "--porcelain", "--untracked-files=all"), stdout = TRUE, stderr = FALSE),
    error = function(e) "dirty"
  )
  commit_status <- attr(commit, "status", exact = TRUE)
  status_status <- attr(status, "status", exact = TRUE)
  list(
    commit = if (length(commit) && (!length(commit_status) || commit_status == 0L)) commit[[1L]] else NA_character_,
    working_tree_clean = !length(status) && (!length(status_status) || status_status == 0L)
  )
}

parse_open_issue_query <- function(output, status = 0L) {
  if (length(status) && status != 0L || !length(output)) {
    return(list(ok = FALSE, count = NA_integer_))
  }
  json <- paste(output, collapse = "\n")
  if (!startsWith(trimws(json), "[")) {
    return(list(ok = FALSE, count = NA_integer_))
  }
  issues <- tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(issues)) {
    return(list(ok = FALSE, count = NA_integer_))
  }
  list(ok = TRUE, count = length(issues))
}
