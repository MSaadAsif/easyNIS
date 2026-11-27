performance_fixture <- function(path, rows) {
  dir.create(path)
  con <- DBI::dbConnect(duckdb::duckdb(
    config = list(
      threads = "4",
      memory_limit = "4 GiB",
      temp_directory = file.path(dirname(path), "fixture-spill")
    )
  ))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "SET max_temp_directory_size = '16 GB'")
  diagnoses <- vapply(
    seq_len(40L),
    function(slot) {
      ordinary <- sprintf(
        "CASE WHEN (h %% %d) < 5 THEN 'Z' || lpad(((h + %d) %% 1800)::VARCHAR, 4, '0') END",
        slot + 4L,
        slot * 113L
      )
      match <- match(slot, c(1L, 9L, 40L))
      if (!is.na(match)) {
        ordinary <- sprintf("CASE WHEN i %% 300 = %d THEN 'I501' ELSE %s END", match - 1L, ordinary)
      }
      sprintf("%s AS I10_DX%d", ordinary, slot)
    },
    character(1)
  )
  procedures <- sprintf(
    "CASE WHEN h %% %d < 3 THEN '0XX' || lpad(((h + %d) %% 800)::VARCHAR, 4, '0') END AS I10_PR%d",
    12:36,
    1:25 * 83L,
    1:25
  )
  days <- sprintf("CASE WHEN I10_PR%d IS NOT NULL THEN age %% 5 END AS PRDAY%d", 1:25, 1:25)
  extras <- sprintf("((h >> %d) %% 4)::INTEGER AS FIELD%d", 1:20, 1:20)
  for (year in 2017:2022) {
    destination <- DBI::dbQuoteString(con, file.path(path, paste0("NIS_", year, ".parquet")))
    fields <- c(
      sprintf("%d AS YEAR", year),
      "i::INTEGER AS KEY_NIS",
      "(1 + i % 4400)::INTEGER AS HOSP_NIS",
      "(1 + i % 200)::INTEGER AS NIS_STRATUM",
      "4.5 + (h % 100) / 100 AS DISCWT",
      "(18 + (h >> 9) % 78)::INTEGER AS AGE",
      "((h >> 17) % 2)::INTEGER AS FEMALE",
      "((h >> 18) % 40 = 0)::INTEGER AS DIED",
      "(1 + (h >> 23) % 20)::INTEGER AS LOS",
      "(1 + (h >> 30) % 4)::INTEGER AS DQTR",
      diagnoses,
      procedures,
      days,
      extras
    )
    sql <- sprintf(
      "COPY (SELECT %s FROM (SELECT i, hash(i, %d) AS h FROM range(%d) AS t(i))) TO %s (FORMAT PARQUET)",
      paste(fields, collapse = ", "),
      year,
      rows,
      destination
    )
    DBI::dbExecute(con, sql)
  }
}
