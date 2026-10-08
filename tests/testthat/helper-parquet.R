write_invented_parquet <- function(session, data, path = tempfile(fileext = ".parquet")) {
  table <- paste0("fixture_", sample.int(1000000L, 1L))
  con <- session$connection
  DBI::dbWriteTable(con, table, data)
  on.exit(DBI::dbRemoveTable(con, table), add = TRUE)
  DBI::dbExecute(con, paste0("COPY ", DBI::dbQuoteIdentifier(con, table), " TO ",
    DBI::dbQuoteString(con, path), " (FORMAT PARQUET)"))
  path
}
