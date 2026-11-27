# Replay the heaviest profiled self-contained SELECT for EXPLAIN ANALYZE.
# Entry-point timings use the original statements and exclude this replay.
args <- commandArgs(TRUE)
root <- args[[1]]
paths <- list.dirs(root, recursive = FALSE, full.names = TRUE)
if (length(args) > 1L) {
  paths <- paths[basename(paths) %in% args[-1L]]
}
for (path in paths) {
  profiles <- list.files(path, "^query-.*[.]json$", full.names = TRUE)
  if (!length(profiles)) {
    next
  }
  qs <- lapply(profiles, jsonlite::read_json)
  read_query <- function(x) {
    grepl("^\\s*(SELECT|WITH)\\b", x$query_name, ignore.case = TRUE) &&
      grepl("read_parquet", x$query_name, fixed = TRUE) &&
      !grepl("COPY\\s+|\\?|duckdb_logs", x$query_name, ignore.case = TRUE)
  }
  candidates <- Filter(read_query, qs)
  if (!length(candidates)) {
    next
  }
  q <- candidates[[which.max(vapply(candidates, "[[", 0, "latency"))]]$query_name
  p <- sub("^.*-", "", path)
  Sys.setenv(DUCKDB_THREADS = p)
  con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = p, memory_limit = paste0(p, "GB"))))
  result <- tryCatch(DBI::dbGetQuery(con, paste("EXPLAIN (ANALYZE, FORMAT JSON)", q)), error = identity)
  if (inherits(result, "error")) {
    writeLines(conditionMessage(result), file.path(path, "explain-replay-error.txt"))
  } else {
    writeLines(result$explain_value, file.path(path, "explain-analyze.json"))
  }
  DBI::dbDisconnect(con, shutdown = TRUE)
}
