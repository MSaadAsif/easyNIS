write_duckdb_parquet <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- nis_duckdb_connect(config = list(threads = "1"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  nis_duckdb_write_parquet(data, path, con)
}

open_duckdb_dataset <- function(path) {
  sources <- list.files(path, pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE)
  con <- nis_duckdb_connect()
  quoted <- DBI::dbQuoteString(con, normalizePath(sources, winslash = "/", mustWork = TRUE))
  parquet <- paste0(
    "read_parquet([",
    paste(quoted, collapse = ", "),
    "], union_by_name = true, hive_partitioning = false)"
  )
  query <- dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
  nis_duckdb_attach_finalizer(query, function() {
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  })
}

# dbplyr skips its missing-value aggregation warning while TESTTHAT is "true"
# and otherwise shows it once per session.
local_sql_na_warnings <- function(.env = parent.frame()) {
  withr::local_envvar(TESTTHAT = "false", .local_envir = .env)
  withr::local_options(rlib_warning_verbosity = "verbose", .local_envir = .env)
}

duckdb_query_fixture <- function(data) {
  con <- nis_duckdb_connect()
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  nis_duckdb_attach_finalizer(dplyr::tbl(con, "fixture"), function() {
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  })
}
