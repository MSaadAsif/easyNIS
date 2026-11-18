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

nis_validate_hive_years <- function(con, sources, scans = NULL) {
  for (index in seq_along(sources)) {
    source <- sources[[index]]
    normalized <- normalizePath(source, winslash = "/", mustWork = TRUE)
    components <- strsplit(normalized, "/", fixed = TRUE)[[1L]]
    partitions <- grep("^YEAR=[0-9]{4}$", components, value = TRUE)
    if (length(partitions) == 0L) next
    partition <- partitions[[length(partitions)]]
    partition_year <- as.integer(sub("^YEAR=", "", partition))
    physical_scan <- if (is.null(scans)) {
      quoted_path <- as.character(DBI::dbQuoteString(con, normalized))
      paste0("read_parquet(", quoted_path, ", hive_partitioning = false)")
    } else {
      scans[[index]]
    }
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

nis_duckdb_normalize_scans <- function(con, sources, scans = NULL,
    alias_case_collisions = TRUE) {
  if (is.null(scans)) {
    scans <- vapply(sources, function(source) {
      nis_duckdb_parquet_sql(con, source, hive_partitioning = FALSE)
    }, character(1))
  }
  schemas <- lapply(scans, function(scan) {
    DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", scan))$column_name
  })
  source_names <- unlist(schemas, use.names = FALSE)
  canonical <- unique(toupper(source_names[grepl("[A-Z]", source_names)]))
  # Keep canonical collisions separately named until DuckDB's union promotes
  # their annual types; its SQL binder resolves identifiers case-insensitively.
  collision_names <- character()
  if (alias_case_collisions) {
    collision_names <- unique(unlist(lapply(schemas, function(fields) {
      groups <- split(fields, toupper(fields))
      names(groups)[lengths(groups) > 1L]
    }), use.names = FALSE))
    collision_names <- intersect(collision_names, canonical)
    # YEAR has special partition and validation handling below.
    collision_names <- setdiff(collision_names, "YEAR")
  }
  collision_fields <- unique(source_names[toupper(source_names) %in% collision_names])
  collision_aliases <- stats::setNames(vapply(collision_fields, function(field) {
    bytes <- paste(sprintf("%02X", as.integer(charToRaw(enc2utf8(field)))),
      collapse = "")
    paste0("__EASYNIS_SCAN_ALIAS_", bytes)
  }, character(1)), collision_fields)
  # Keep generated identifiers outside the input schema namespace.
  while (any(collision_aliases %in% source_names)) {
    collision_aliases <- paste0(collision_aliases, "_X")
  }
  alias_targets <- stats::setNames(toupper(collision_fields), collision_aliases)

  normalized <- vapply(seq_along(scans), function(index) {
    scan <- scans[[index]]
    old <- schemas[[index]]
    targets <- old
    collision <- old %in% names(collision_aliases)
    targets[collision] <- unname(collision_aliases[old[collision]])
    rename <- !collision & old != toupper(old) & toupper(old) %in% canonical
    targets[rename] <- toupper(old[rename])
    changed <- targets != old
    if (!any(changed)) return(scan)
    identifiers <- as.character(DBI::dbQuoteIdentifier(con, old[changed]))
    aliases <- as.character(DBI::dbQuoteIdentifier(con, targets[changed]))
    changes <- paste(identifiers, "AS", aliases, collapse = ", ")
    paste0("(SELECT * RENAME (", changes, ") FROM ", scan, ")")
  }, character(1))
  attr(normalized, "easyNIS_case_aliases") <- alias_targets
  normalized
}

nis_duckdb_query_from_parquet <- function(con, sources, scans = NULL) {
  scans <- nis_duckdb_normalize_scans(con, sources, scans,
    alias_case_collisions = TRUE)
  alias_targets <- attr(scans, "easyNIS_case_aliases")
  normalized <- normalizePath(sources, winslash = "/", mustWork = TRUE)
  is_hive <- grepl("(^|/)YEAR=[0-9]{4}/", normalized)
  scans <- vapply(seq_along(sources), function(index) {
    scan <- scans[[index]]
    schema <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", scan))
    year_rows <- which(toupper(schema$column_name) == "YEAR")
    if (!is_hive[[index]] && length(year_rows) == 0L) {
      return(paste0("SELECT * FROM ", scan))
    }

    if (is_hive[[index]]) {
      components <- strsplit(normalized[[index]], "/", fixed = TRUE)[[1L]]
      partition <- grep("^YEAR=[0-9]{4}$", components, value = TRUE)
      partition_year <- as.integer(sub("^YEAR=", "", partition[[length(partition)]]))
    }
    if (length(year_rows) == 0L) {
      return(paste0("SELECT ", partition_year, "::INTEGER AS YEAR, * FROM ", scan))
    }

    year_name <- schema$column_name[[year_rows[[1L]]]]
    year_column <- as.character(DBI::dbQuoteIdentifier(con, year_name))
    year_double <- paste0("TRY_CAST(", year_column, " AS DOUBLE)")
    year_value <- if (is_hive[[index]]) {
      paste0("CASE WHEN ", year_column, " IS NULL OR isnan(",
        year_double, ") THEN ", partition_year, " ELSE TRY_CAST(",
        year_column, " AS INTEGER) END")
    } else {
      paste0("CASE WHEN isnan(", year_double,
        ") THEN NULL ELSE TRY_CAST(", year_column, " AS INTEGER) END")
    }
    paste0("SELECT ", year_value, " AS YEAR, * EXCLUDE (", year_column,
      ") FROM ", scan)
  }, character(1))
  parquet <- paste0("(", paste(scans, collapse = " UNION ALL BY NAME "), ")")
  if (length(alias_targets) > 0L) {
    union_schema <- DBI::dbGetQuery(con,
      paste("DESCRIBE SELECT * FROM", parquet))$column_name
    output_names <- unname(alias_targets[union_schema])
    output_names[is.na(output_names)] <- union_schema[is.na(output_names)]
    output_order <- unique(output_names)
    columns <- vapply(output_order, function(output_name) {
      fields <- union_schema[output_names == output_name]
      quoted <- as.character(DBI::dbQuoteIdentifier(con, fields))
      value <- if (length(fields) > 1L) {
        paste0("COALESCE(", paste(quoted, collapse = ", "), ")")
      } else {
        quoted
      }
      paste(value, "AS", as.character(DBI::dbQuoteIdentifier(con, output_name)))
    }, character(1))
    parquet <- paste0("(SELECT ", paste(columns, collapse = ", "),
      " FROM ", parquet, ")")
  }
  dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM ", parquet)))
}

nis_validate_year_values <- function(con, sources, scans = NULL) {
  invalid <- character()
  for (index in seq_along(sources)) {
    source <- sources[[index]]
    normalized <- normalizePath(source, winslash = "/", mustWork = TRUE)
    scan <- if (is.null(scans)) {
      quoted_path <- as.character(DBI::dbQuoteString(con, normalized))
      paste0("read_parquet(", quoted_path, ", hive_partitioning = false)")
    } else {
      scans[[index]]
    }
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
