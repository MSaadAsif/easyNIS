nis_open_scan <- function(path, partition_year, index, con, reader) {
  owner <- NULL
  if (reader == "arrow") {
    owner <- arrow::open_dataset(path, partitioning = character())
    name <- paste0("easyNIS_arrow_", index)
    duckdb::duckdb_register_arrow(con, name, owner)
    scan <- as.character(DBI::dbQuoteIdentifier(con, name))
  } else {
    scan <- nis_parquet_scan(con, path)
  }
  schema <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", scan))
  year_index <- match("YEAR", toupper(schema$column_name))
  physical <- NULL
  if (!is.na(year_index)) {
    column <- as.character(DBI::dbQuoteIdentifier(con, schema$column_name[[year_index]]))
    type <- toupper(schema$column_type[[year_index]])
    integer <- grepl("^U?(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT)$", type)
    decimal <- grepl("^DECIMAL\\([0-9]+, ?[0-9]+\\)$", type)
    physical <- list(column = column, type = type,
      small_integer = type %in% c("TINYINT", "UTINYINT", "SMALLINT", "USMALLINT", "INTEGER"),
      integer = integer, numeric = integer || decimal || type %in% c("FLOAT", "REAL", "DOUBLE"),
      double = paste0("TRY_CAST(", column, " AS DOUBLE)"))
  }
  list(path = path, scan = scan, schema = schema, year = partition_year,
    physical = physical, owner = owner)
}

nis_open_validate_partition <- function(source, con) {
  if (is.na(source$year) || is.null(source$physical)) return(invisible(NULL))
  physical <- source$physical
  mismatch <- if (physical$integer) {
    paste(physical$column, "<>", source$year)
  } else if (physical$numeric) {
    paste0(physical$column, " IS NOT NULL AND NOT isnan(", physical$double,
      ") AND ", physical$double, " <> ", source$year)
  } else {
    paste0(physical$column, " IS NOT NULL AND TRY_CAST(", physical$column,
      " AS BIGINT) IS DISTINCT FROM ", source$year)
  }
  if (nis_open_invalid_year_rows(con, source$scan, mismatch)) {
    cli::cli_abort(paste0(
      "Non-missing physical `YEAR` values conflict with Hive partition ",
      "{.val {paste0('YEAR=', source$year)}} in {.path {source$path}}."
    ))
  }
  invisible(NULL)
}

nis_open_invalid_year_rows <- function(con, scan, predicate) {
  nrow(DBI::dbGetQuery(con, paste("SELECT 1 FROM", scan, "WHERE", predicate, "LIMIT 1"))) > 0L
}

nis_open_check_year_values <- function(sources, con) {
  invalid <- Filter(function(source) {
    physical <- source$physical
    if (is.null(physical) || physical$small_integer) return(FALSE)
    # Numeric Hive values already match the partition or are missing.
    if (!is.na(source$year) && physical$numeric) return(FALSE)
    year <- physical$double
    predicate <- paste0(physical$column, " IS NOT NULL AND (", year,
      " IS NULL OR (NOT isnan(", year, ") AND (", year, " <> floor(", year,
      ") OR ", year, " < -2147483648 OR ", year, " > 2147483647)))")
    nis_open_invalid_year_rows(con, source$scan, predicate)
  }, sources)
  if (length(invalid)) {
    paths <- vapply(invalid, `[[`, character(1), "path") # nolint: object_usage_linter
    cli::cli_abort(paste0("Invalid `YEAR` values were found in {.path {paths}}; ",
      "values must be whole numbers within the integer range."))
  }
}

nis_parquet_scan <- function(con, paths) {
  patterns <- gsub("[", "[[]", paths, fixed = TRUE)
  patterns <- gsub("*", "[*]", patterns, fixed = TRUE)
  patterns <- gsub("?", "[?]", patterns, fixed = TRUE)
  quoted <- as.character(DBI::dbQuoteString(con, patterns))
  argument <- if (length(quoted) == 1L) quoted else paste0("[", paste(quoted, collapse = ", "), "]")
  paste0("read_parquet(", argument, ", hive_partitioning = false)")
}

nis_open_project_sources <- function(sources, con) {
  same_scan <- function(left, right) {
    is.null(left$owner) && is.null(right$owner) && identical(left$year, right$year) &&
      identical(left$schema[c("column_name", "column_type")],
        right$schema[c("column_name", "column_type")])
  }
  breaks <- vapply(seq_len(length(sources) - 1L), function(i) {
    !same_scan(sources[[i]], sources[[i + 1L]])
  }, logical(1))
  runs <- split(sources, cumsum(c(TRUE, breaks)))
  vapply(runs, function(run) {
    source <- run[[1L]]
    if (length(run) > 1L) {
      paths <- vapply(run, "[[", character(1), "path")
      source$scan <- nis_parquet_scan(con, paths)
    }
    nis_open_project_year(source)
  }, character(1))
}

nis_open_project_year <- function(source) {
  scan <- source$scan
  physical <- source$physical
  partition <- source$year
  if (!is.na(partition)) {
    year_value <- paste0(partition, "::INTEGER")
  } else if (is.null(physical)) {
    return(paste("SELECT * FROM", scan))
  } else if (physical$type == "INTEGER") {
    year_value <- physical$column
  } else if (physical$integer) {
    year_value <- paste0("CAST(", physical$column, " AS INTEGER)")
  } else {
    year_value <- paste0("CASE WHEN isnan(", physical$double,
      ") THEN NULL ELSE TRY_CAST(", physical$column, " AS INTEGER) END")
  }
  exclude <- if (is.null(physical)) "" else paste0(" EXCLUDE (", physical$column, ")")
  paste0("SELECT ", year_value, " AS YEAR, *", exclude, " FROM ", scan)
}
