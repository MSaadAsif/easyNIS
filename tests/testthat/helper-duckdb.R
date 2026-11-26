write_duckdb_parquet <- local({
  writer <- NULL
  function(data, path) {
    if (is.null(writer)) {
      writer <<- nis_duckdb_connect(config = list(threads = "1"))
      withr::defer(
        {
          if (DBI::dbIsValid(writer)) {
            DBI::dbDisconnect(writer, shutdown = TRUE)
          }
          writer <<- NULL
        },
        envir = testthat::teardown_env()
      )
    }
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    DBI::dbWriteTable(writer, "fixture", data, temporary = TRUE, overwrite = TRUE)
    destination <- DBI::dbQuoteString(writer, normalizePath(path, winslash = "/", mustWork = FALSE))
    DBI::dbExecute(writer, paste("COPY fixture TO", destination, "(FORMAT PARQUET)"))
    invisible(path)
  }
})

open_duckdb_dataset <- function(path, .env = parent.frame()) {
  sources <- list.files(path, pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE)
  con <- nis_duckdb_connect()
  withr::defer(
    {
      if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
    },
    envir = .env
  )
  quoted <- DBI::dbQuoteString(con, normalizePath(sources, winslash = "/", mustWork = TRUE))
  parquet <- paste0(
    "read_parquet([",
    paste(quoted, collapse = ", "),
    "], union_by_name = true, hive_partitioning = false)"
  )
  dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
}

# dbplyr skips its missing-value aggregation warning while TESTTHAT is "true"
# and otherwise shows it once per session.
local_sql_na_warnings <- function(.env = parent.frame()) {
  withr::local_envvar(TESTTHAT = "false", .local_envir = .env)
  withr::local_options(rlib_warning_verbosity = "verbose", .local_envir = .env)
}

duckdb_query_fixture <- function(data, .env = parent.frame()) {
  con <- nis_duckdb_connect()
  withr::defer(
    {
      if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
    },
    envir = .env
  )
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  dplyr::tbl(con, "fixture")
}
