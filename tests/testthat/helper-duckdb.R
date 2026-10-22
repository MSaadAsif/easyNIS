write_duckdb_parquet <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  nis_duckdb_write_parquet(data, path) # nolint: object_usage_linter
}

open_duckdb_dataset <- function(path) {
  sources <- list.files(path, pattern = "[.]parquet$", recursive = TRUE,
    full.names = TRUE)
  con <- nis_duckdb_connect() # nolint: object_usage_linter
  parquet <- nis_duckdb_parquet_sql(con, sources) # nolint: object_usage_linter
  query <- dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
  nis_duckdb_attach_finalizer(query, con) # nolint: object_usage_linter
}

duckdb_query_fixture <- function(data) {
  con <- nis_duckdb_connect() # nolint: object_usage_linter
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  nis_duckdb_attach_finalizer(dplyr::tbl(con, "fixture"), con) # nolint: object_usage_linter
}
