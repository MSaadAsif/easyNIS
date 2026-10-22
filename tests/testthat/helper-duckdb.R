write_duckdb_parquet <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  nis_duckdb_write_parquet(data, path)
}

open_duckdb_dataset <- function(path) {
  sources <- list.files(path, pattern = "[.]parquet$", recursive = TRUE,
    full.names = TRUE)
  con <- nis_duckdb_connect()
  parquet <- nis_duckdb_parquet_sql(con, sources)
  query <- dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
  nis_duckdb_attach_finalizer(query, con)
}

duckdb_query_fixture <- function(data) {
  con <- nis_duckdb_connect()
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  nis_duckdb_attach_finalizer(dplyr::tbl(con, "fixture"), con)
}
