nis_duckdb_connect <- function(config = list()) {
  DBI::dbConnect(duckdb::duckdb(config = config))
}

nis_duckdb_open_data <- function() {
  config <- nis_duckdb_workload_settings(getOption("easyNIS.duckdb_config", list()))
  root <- if (is.null(config$temp_directory)) tempdir() else config$temp_directory
  if (!dir.exists(root)) {
    cli::cli_abort("The DuckDB `temp_directory` must name an existing directory.")
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  spill <- tempfile("easynis-spill-", tmpdir = root)
  if (!dir.create(spill, mode = "0700")) {
    cli::cli_abort("Could not create a private DuckDB spill directory.")
  }
  spill <- normalizePath(spill, winslash = "/", mustWork = TRUE)
  config$temp_directory <- spill
  con <- NULL
  release <- function() {
    on.exit(nis_remove_owned_directory(spill), add = TRUE)
    if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }
  on.exit(if (is.null(con)) release(), add = TRUE)
  con <- nis_duckdb_connect(config)
  list(con = con, release = release)
}

nis_remove_owned_directory <- function(path) {
  if (dir.exists(path) && identical(normalizePath(path, winslash = "/", mustWork = TRUE), path)) {
    unlink(path, recursive = TRUE)
  }
  invisible(NULL)
}

nis_duckdb_workload_settings <- function(config) {
  supported <- c("memory_limit", "threads", "temp_directory", "max_temp_directory_size",
    "preserve_insertion_order")
  keys <- names(config)
  if (!is.list(config) || length(keys) != length(config) || anyDuplicated(keys) ||
      !all(keys %in% supported)) {
    cli::cli_abort("Option `easyNIS.duckdb_config` must be a named list of DuckDB workload settings.")
  }
  lapply(config, nis_duckdb_setting_text)
}

nis_duckdb_setting_text <- function(value) {
  if (!is.atomic(value) || length(value) != 1L || is.na(value)) {
    cli::cli_abort("Each DuckDB workload setting must have one non-missing value.")
  }
  as.character(value)
}

nis_duckdb_attach_finalizer <- function(tbl, release, owners = list()) {
  finalizer <- new.env(parent = emptyenv())
  reg.finalizer(finalizer, function(e) release(), onexit = TRUE)
  tbl$src$.easyNIS_connection_finalizer <- finalizer
  if (length(owners)) tbl$src$.easyNIS_arrow_refs <- owners
  tbl
}

nis_duckdb_write_parquet <- function(data, path, con) {
  table <- "easyNIS_fixture"
  DBI::dbWriteTable(con, table, data, temporary = TRUE, overwrite = TRUE)
  destination <- as.character(DBI::dbQuoteString(con,
    normalizePath(path, winslash = "/", mustWork = FALSE)))
  statement <- paste0("COPY ", as.character(DBI::dbQuoteIdentifier(con, table)),
    " TO ", destination, " (FORMAT PARQUET)")
  DBI::dbExecute(con, statement)
  invisible(path)
}
