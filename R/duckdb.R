nis_duckdb_connect <- function() {
  DBI::dbConnect(duckdb::duckdb())
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
    is_null <- rlang::expr(is.na(!!value))
    is_nan <- dbplyr::sql_expr(isnan(!!dbplyr::ident(column)), # nolint: object_usage_linter
      con = data$src$con)
    return(rlang::expr(!!is_null | !!is_nan))
  }
  rlang::expr(is.na(!!value))
}

nis_duckdb_attach_finalizer <- function(tbl, con) {
  finalizer <- new.env(parent = emptyenv())
  reg.finalizer(finalizer, function(e) {
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }, onexit = TRUE)
  tbl$src$.easyNIS_connection_finalizer <- finalizer
  tbl
}

nis_duckdb_parquet_sql <- function(con, sources) {
  paths <- vapply(sources, function(path) {
    path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    as.character(DBI::dbQuoteString(con, path))
  }, character(1))
  paste0("read_parquet([", paste(paths, collapse = ", "),
    "], union_by_name = true, hive_partitioning = true)")
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

nis_sql_match <- function(prefix, column) {
  per_prefix <- lapply(prefix, function(code) {
    rlang::expr(substr(!!rlang::sym(column), 1L, !!nchar(code)) == !!code)
  })
  rlang::expr(dplyr::coalesce(!!reduce_or(per_prefix), FALSE))
}

nis_and_expr <- function(left, right) {
  rlang::expr(dplyr::if_else(!!left, !!right, FALSE))
}
