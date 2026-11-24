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
    on.exit(nis_remove_spill_directory(spill), add = TRUE)
    if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }
  on.exit(if (is.null(con)) release(), add = TRUE)
  con <- nis_duckdb_connect(config)
  list(con = con, release = release)
}

nis_remove_spill_directory <- function(path) {
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

nis_names <- function(data) {
  if (inherits(data, "tbl_sql")) colnames(data) else names(data)
}

nis_is_finite_expr <- function(data, column) {
  if (inherits(data, "tbl_sql")) {
    return(dbplyr::sql_expr(isfinite(!!dbplyr::ident(column)), # nolint: object_usage_linter
      con = data$src$con))
  }
  rlang::expr(is.finite(!!rlang::sym(column)))
}

nis_is_missing_expr <- function(data, column) {
  value <- rlang::sym(column)
  if (inherits(data, "tbl_sql")) {
    numeric_types <- c("TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT",
      "UTINYINT", "USMALLINT", "UINTEGER", "UBIGINT", "UHUGEINT",
      "FLOAT", "REAL", "DOUBLE", "DECIMAL")
    identifier <- as.character(DBI::dbQuoteIdentifier(data$src$con, column))
    types <- paste(as.character(DBI::dbQuoteString(data$src$con, numeric_types)),
      collapse = ", ")
    return(dbplyr::sql(paste0("(", identifier, " IS NULL OR (typeof(",
      identifier, ") IN (", types, ") AND isnan(TRY_CAST(", identifier,
      " AS DOUBLE))))")))
  }
  rlang::expr(is.na(!!value))
}

nis_internal_names <- function(data, reserved, candidates) {
  if (!inherits(data, "tbl_sql")) {
    return(utils::tail(make.unique(c(reserved, candidates)), length(candidates)))
  }
  keys <- nis_sql_identifier_key(c(reserved, candidates))
  unique_keys <- make.unique(keys)
  candidate_keys <- utils::tail(keys, length(candidates))
  suffix <- substring(utils::tail(unique_keys, length(candidates)), nchar(candidate_keys) + 1L)
  paste0(candidates, suffix)
}

nis_sql_identifier_key <- function(names) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", names)
}

nis_duckdb_attach_finalizer <- function(tbl, release, owners = list()) {
  finalizer <- new.env(parent = emptyenv())
  reg.finalizer(finalizer, function(e) release(), onexit = TRUE)
  tbl$src$.easyNIS_connection_finalizer <- finalizer
  if (length(owners)) tbl$src$.easyNIS_arrow_refs <- owners
  tbl
}

nis_duckdb_write_parquet <- function(data, path) {
  con <- nis_duckdb_connect() # nolint: object_usage_linter
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  table <- "easyNIS_fixture"
  DBI::dbWriteTable(con, table, data, temporary = TRUE)
  destination <- as.character(DBI::dbQuoteString(con,
    normalizePath(path, winslash = "/", mustWork = FALSE)))
  statement <- paste0("COPY ", as.character(DBI::dbQuoteIdentifier(con, table)),
    " TO ", destination, " (FORMAT PARQUET)")
  DBI::dbExecute(con, statement)
  invisible(path)
}

nis_collect <- function(x) {
  if (is.data.frame(x)) return(x)
  tryCatch(
    dplyr::collect(x),
    error = function(error) {
      if (grepl("invalid string encoding|invalid UTF-8",
        conditionMessage(error), ignore.case = TRUE)) {
        cli::cli_abort(c(
          "A string column in the Parquet input is not valid UTF-8.",
          i = paste0(
            "This usually happens when converting HCUP ASCII files without ",
            "declaring their source encoding.",
            " Re-convert with the correct encoding, for example Latin-1 to UTF-8."
          )
        ), parent = error)
      }
      stop(error)
    }
  )
}
