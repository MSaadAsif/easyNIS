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

nis_numeric_value_expr <- function(column) {
  value <- rlang::sym(column)
  rlang::expr(as.double(!!value))
}

nis_validate_hive_years <- function(con, sources) {
  for (source in sources) {
    normalized <- normalizePath(source, winslash = "/", mustWork = TRUE)
    components <- strsplit(normalized, "/", fixed = TRUE)[[1L]]
    partitions <- grep("^YEAR=[0-9]{4}$", components, value = TRUE)
    if (length(partitions) == 0L) next
    partition <- partitions[[length(partitions)]]
    partition_year <- as.integer(sub("^YEAR=", "", partition))
    quoted_path <- as.character(DBI::dbQuoteString(con, normalized))
    physical_scan <- paste0("read_parquet(", quoted_path,
      ", hive_partitioning = false)")
    schema <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", physical_scan))
    year_rows <- which(toupper(schema$column_name) == "YEAR")
    if (length(year_rows) == 0L) next
    year_column <- as.character(DBI::dbQuoteIdentifier(con,
      schema$column_name[[year_rows[[1L]]]]))
    year_type <- toupper(schema$column_type[[year_rows[[1L]]]])
    is_numeric <- grepl(
      "^(U?TINYINT|U?SMALLINT|U?INTEGER|U?BIGINT|U?HUGEINT|FLOAT|REAL|DOUBLE|DECIMAL)",
      year_type
    )
    cast_year <- paste0("TRY_CAST(", year_column,
      if (is_numeric) " AS DOUBLE)" else " AS BIGINT)")
    mismatch <- if (is_numeric) {
      paste0(year_column, " IS NOT NULL AND NOT isnan(", cast_year,
        ") AND ", cast_year, " <> ", partition_year)
    } else {
      paste0(year_column, " IS NOT NULL AND ", cast_year,
        " IS DISTINCT FROM ", partition_year)
    }
    result <- DBI::dbGetQuery(con, paste0(
      "SELECT COUNT(*) AS n FROM ", physical_scan, " WHERE ", mismatch
    ))
    if (result$n[[1L]] > 0L) {
      cli::cli_abort(paste0(
        "Non-missing physical `YEAR` values conflict with Hive partition ",
        "{.val {partition}} in {.path {source}}."
      ))
    }
  }
  invisible(NULL)
}

nis_duckdb_attach_finalizer <- function(tbl, con) {
  finalizer <- new.env(parent = emptyenv())
  reg.finalizer(finalizer, function(e) {
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }, onexit = TRUE)
  tbl$src$.easyNIS_connection_finalizer <- finalizer
  tbl
}

nis_duckdb_parquet_sql <- function(con, sources, hive_partitioning = FALSE) {
  paths <- vapply(sources, function(path) {
    path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    as.character(DBI::dbQuoteString(con, path))
  }, character(1))
  paste0("read_parquet([", paste(paths, collapse = ", "),
    "], union_by_name = true, hive_partitioning = ",
    if (hive_partitioning) "true" else "false", ")")
}

nis_duckdb_query_from_parquet <- function(con, sources) {
  normalized <- normalizePath(sources, winslash = "/", mustWork = TRUE)
  is_hive <- grepl("(^|/)YEAR=[0-9]{4}/", normalized)
  scans <- vapply(c(FALSE, TRUE), function(hive) {
    selected <- sources[is_hive == hive]
    if (length(selected) == 0L) return(NA_character_)
    paste0("SELECT * FROM ", nis_duckdb_parquet_sql(con, selected,
      hive_partitioning = hive))
  }, character(1))
  scans <- scans[!is.na(scans)]
  parquet <- paste0("(", paste(scans, collapse = " UNION ALL BY NAME "), ")")
  raw_query <- dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
  year_name <- colnames(raw_query)[toupper(colnames(raw_query)) == "YEAR"]
  if (length(year_name) == 0L) return(raw_query)

  year_column <- as.character(DBI::dbQuoteIdentifier(con, year_name[[1L]]))
  year_double <- paste0("TRY_CAST(", year_column, " AS DOUBLE)")
  normalized_year <- paste0("CASE WHEN isnan(", year_double,
    ") THEN NULL ELSE TRY_CAST(", year_column, " AS INTEGER) END")
  sql <- paste0("SELECT ", normalized_year, " AS YEAR, ",
    "* EXCLUDE (", year_column, ") FROM ", parquet)
  dplyr::tbl(con, dbplyr::sql(sql))
}

nis_validate_year_values <- function(con, sources) {
  invalid <- character()
  for (source in sources) {
    normalized <- normalizePath(source, winslash = "/", mustWork = TRUE)
    quoted_path <- as.character(DBI::dbQuoteString(con, normalized))
    scan <- paste0("read_parquet(", quoted_path,
      ", hive_partitioning = false)")
    schema <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", scan))
    year_rows <- which(toupper(schema$column_name) == "YEAR")
    if (length(year_rows) == 0L) next
    year_column <- as.character(DBI::dbQuoteIdentifier(con,
      schema$column_name[[year_rows[[1L]]]]))
    year_double <- paste0("TRY_CAST(", year_column, " AS DOUBLE)")
    is_out_of_range <- paste0("(", year_double, " < -2147483648 OR ",
      year_double, " > 2147483647)")
    is_fractional <- paste0("(", year_double, " <> floor(", year_double,
      "))")
    invalid_value <- paste0("(", year_column, " IS NOT NULL AND (",
      year_double, " IS NULL OR (NOT isnan(", year_double, ") AND (",
      is_fractional, " OR ", is_out_of_range, "))))")
    count <- DBI::dbGetQuery(con, paste0(
      "SELECT COUNT(*) AS n FROM ", scan, " WHERE ", invalid_value
    ))$n[[1L]]
    if (count > 0L) invalid <- c(invalid, source)
  }
  if (length(invalid) > 0L) {
    cli::cli_abort(paste0(
      "Invalid `YEAR` values were found in {.path {invalid}}; values must be ",
      "whole numbers within the integer range."
    ))
  }
  invisible(NULL)
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
