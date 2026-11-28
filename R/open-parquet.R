nis_open_plan_parquet <- function(parts, con, reader) {
  sources <- Map(
    nis_open_scan,
    parts$path,
    parts$partition_year,
    seq_len(nrow(parts)),
    MoreArgs = list(con = con, reader = reader)
  )
  scans <- nis_open_group_scans(sources, con)
  for (scan in scans) {
    nis_open_validate_partition(scan, con)
  }
  nis_open_check_year_values(scans, con)
  list(
    query = nis_open_parquet_query(scans, con),
    sources = sources,
    names_by_part = lapply(sources, function(source) source$schema$column_name),
    owners = Filter(Negate(is.null), lapply(sources, function(source) source$owner))
  )
}

nis_open_parquet_query <- function(scans, con) {
  projections <- vapply(scans, nis_open_project_year, character(1))
  union <- paste(projections, collapse = " UNION ALL BY NAME ")
  dbplyr::tbl_sql(
    c("duckdb_connection", "dbi"),
    src = dbplyr::src_dbi(con),
    from = dbplyr::sql(paste0("SELECT * FROM (", union, ")"))
  )
}

nis_open_scan <- function(path, partition_year, index, con, reader) {
  owner <- NULL
  if (reader == "arrow") {
    owner <- nis_open_arrow_dataset(path)
    name <- paste0("easyNIS_arrow_", index)
    duckdb::duckdb_register_arrow(con, name, owner)
    scan <- as.character(DBI::dbQuoteIdentifier(con, name))
  } else {
    scan <- nis_parquet_scan(con, path)
  }
  schema <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", scan))[c("column_name", "column_type")]
  year_index <- match("YEAR", toupper(schema$column_name))
  physical <- NULL
  if (!is.na(year_index)) {
    column <- as.character(DBI::dbQuoteIdentifier(con, schema$column_name[[year_index]]))
    type <- toupper(schema$column_type[[year_index]])
    integer <- grepl("^U?(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT)$", type)
    decimal <- grepl("^DECIMAL\\([0-9]+, ?[0-9]+\\)$", type)
    physical <- list(
      column = column,
      type = type,
      small_integer = type %in% c("TINYINT", "UTINYINT", "SMALLINT", "USMALLINT", "INTEGER"),
      integer = integer,
      numeric = integer || decimal || type %in% c("FLOAT", "REAL", "DOUBLE"),
      double = paste0("TRY_CAST(", column, " AS DOUBLE)")
    )
  }
  list(path = path, scan = scan, schema = schema, year = partition_year, physical = physical, owner = owner)
}

nis_open_arrow_dataset <- function(path) {
  dataset <- arrow::open_dataset(path, partitioning = character())
  reader <- R6::R6Class(
    "nis_arrow_dataset",
    inherit = arrow::FileSystemDataset,
    public = list(NewScan = function() {
      # Parquet read-ahead scales with the batch size for each active scan.
      builder <- super$NewScan()
      builder$BatchSize(8192L)
      builder
    })
  )
  reader$new(dataset$pointer())
}

nis_open_validate_partition <- function(scan, con) {
  if (is.na(scan$year) || is.null(scan$physical)) {
    return(invisible(NULL))
  }
  physical <- scan$physical
  mismatch <- if (physical$integer) {
    paste(physical$column, "<>", scan$year)
  } else if (physical$numeric) {
    paste0(
      physical$column,
      " IS NOT NULL AND NOT isnan(",
      physical$double,
      ") AND ",
      physical$double,
      " <> ",
      scan$year
    )
  } else {
    paste0(physical$column, " IS NOT NULL AND TRY_CAST(", physical$column, " AS BIGINT) IS DISTINCT FROM ", scan$year)
  }
  path <- nis_open_invalid_paths(con, scan, mismatch, first = TRUE)
  if (length(path)) {
    cli::cli_abort(paste0(
      "Non-missing physical `YEAR` values conflict with Hive partition ",
      "{.val {paste0('YEAR=', scan$year)}} in {.path {path}}."
    ))
  }
  invisible(NULL)
}

nis_open_invalid_year_rows <- function(con, scan, predicate) {
  nrow(DBI::dbGetQuery(con, paste("SELECT 1 FROM", scan, "WHERE", predicate, "LIMIT 1"))) > 0L
}

nis_open_invalid_paths <- function(con, scan, predicate, first = FALSE) {
  if (!nis_open_invalid_year_rows(con, scan$scan, predicate)) {
    return(character())
  }
  paths <- scan$paths
  if (length(paths) == 1L) {
    return(paths)
  }

  # Reopen individual parts only to attribute a failed grouped scan.
  invalid <- logical(length(paths))
  for (i in seq_along(paths)) {
    part <- nis_parquet_scan(con, paths[[i]])
    invalid[[i]] <- nis_open_invalid_year_rows(con, part, predicate)
    if (first && invalid[[i]]) return(paths[[i]])
  }
  if (!any(invalid)) {
    cli::cli_abort("No individual Parquet part reproduced the grouped `YEAR` validation failure in {.path {paths}}.")
  }
  paths[invalid]
}

nis_open_check_year_values <- function(sources, con) {
  invalid <- lapply(sources, function(source) {
    predicate <- nis_open_year_range_predicate(source)
    if (is.null(predicate)) {
      return(character())
    }
    nis_open_invalid_paths(con, source, predicate)
  })
  paths <- unlist(invalid, use.names = FALSE)
  if (length(paths)) {
    cli::cli_abort(paste0(
      "Invalid `YEAR` values were found in {.path {paths}}; ",
      "values must be whole numbers within the integer range."
    ))
  }
}

nis_open_year_range_predicate <- function(source) {
  physical <- source$physical
  if (is.null(physical) || physical$small_integer) {
    return(NULL)
  }
  # Numeric Hive values already match the partition or are missing.
  if (!is.na(source$year) && physical$numeric) {
    return(NULL)
  }
  if (physical$integer) {
    # A comparison on the native column lets Parquet skip valid row groups.
    upper <- paste(physical$column, "> 2147483647")
    if (startsWith(physical$type, "U")) {
      return(upper)
    }
    return(paste(physical$column, "< -2147483648 OR", upper))
  }
  year <- physical$double
  paste0(
    physical$column,
    " IS NOT NULL AND (",
    year,
    " IS NULL OR (NOT isnan(",
    year,
    ") AND (",
    year,
    " <> floor(",
    year,
    ") OR ",
    year,
    " < -2147483648 OR ",
    year,
    " > 2147483647)))"
  )
}

nis_parquet_scan <- function(con, paths) {
  paste0("read_parquet(", nis_parquet_paths(con, paths), ", hive_partitioning = false)")
}

nis_parquet_paths <- function(con, paths) {
  patterns <- gsub("[", "[[]", paths, fixed = TRUE)
  patterns <- gsub("*", "[*]", patterns, fixed = TRUE)
  patterns <- gsub("?", "[?]", patterns, fixed = TRUE)
  quoted <- as.character(DBI::dbQuoteString(con, patterns))
  if (length(quoted) == 1L) quoted else paste0("[", paste(quoted, collapse = ", "), "]")
}

nis_open_group_scans <- function(sources, con) {
  same_scan <- function(left, right) {
    is.null(left$owner) &&
      is.null(right$owner) &&
      identical(left$year, right$year) &&
      identical(left$schema, right$schema)
  }
  breaks <- vapply(
    seq_len(length(sources) - 1L),
    function(i) {
      !same_scan(sources[[i]], sources[[i + 1L]])
    },
    logical(1)
  )
  runs <- split(sources, cumsum(c(TRUE, breaks)))
  lapply(runs, function(run) {
    source <- run[[1L]]
    source$paths <- vapply(run, "[[", character(1), "path")
    if (length(run) > 1L) {
      source$scan <- nis_parquet_scan(con, source$paths)
    }
    source
  })
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
    year_value <- paste0(
      "CASE WHEN isnan(",
      physical$double,
      ") THEN NULL ELSE TRY_CAST(",
      physical$column,
      " AS INTEGER) END"
    )
  }
  exclude <- if (is.null(physical)) "" else paste0(" EXCLUDE (", physical$column, ")")
  paste0("SELECT ", year_value, " AS YEAR, *", exclude, " FROM ", scan)
}
