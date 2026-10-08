#' Inspect converted local parquet components
#'
#' Experimental structural import, not a verified annual adapter. Raw fields
#' and types are preserved in lazy temporary DuckDB views. All shards in a
#' component must have identical flat schemas. Case-insensitive field collisions
#' are rejected before DuckDB can rename them. Source paths are quoted as SQL
#' literals, and source files must remain unchanged while the relation is used.
#' Size and modification time are checked before package queries. This is a
#' metadata guard, not a content checksum; same-size changes with restored times
#' cannot be detected. Do not edit sources during a session.
#'
#' Supplied components must have unique nonmissing join keys. Hospital joins use
#' `YEAR` and `HOSP_NIS`; other component joins use `YEAR` and `KEY_NIS`.
#' Every core row must match each supplied component. Shared non-key columns
#' must agree on matched rows; only one copy is retained. Unused component rows
#' are recorded in provenance. No component is inferred from merged field names.
#'
#' @param session An open session returned by [nis_open()].
#' @param core Local parquet file paths or one directory of parquet shards.
#' @param year A single whole data year from 2017 through 2022.
#' @param hospital,severity,diagnosis_procedure_groups Optional local component
#'   file paths or directories. `NULL` means not supplied, not source-unavailable.
#' @param provenance A named list of conversion information. Supply `conversion`,
#'   `revision`, `prefiltered`, `labels`, and `missing_reasons` when known.
#'   These statements are retained as user declarations, not verified facts.
#' @return A `nis_data` list with session, lazy view, year, raw schema, source
#'   file metadata, component join receipts, and provenance. This experimental
#'   relation is not approved for survey inference. Use [nis_validate()] to
#'   inspect structural issues and [nis_collect()] for explicit projections.
#'   Structural field/year/join failures signal a `nis_structure_error`
#'   condition with `check`, `component`, `fields`, and aggregate `affected`.
#'   Affected counts are rows unless the message explicitly identifies key
#'   groups. Schema-only failures have an unknown affected count. Conditions
#'   contain no discharge identifiers or source row values.
#' @export
#' @examples
#' session <- nis_open()
#' path <- tempfile(fileext = ".parquet")
#' DBI::dbWriteTable(session$connection, "invented", nis_synthetic_data()$core)
#' destination <- DBI::dbQuoteString(session$connection, path)
#' DBI::dbExecute(session$connection,
#'   paste0("COPY invented TO ", destination, " (FORMAT PARQUET)"))
#' stays <- nis_import(session, path, year = 2022)
#' nis_collect(stays, c("KEY_NIS", "DISCWT"), limit = 3)
#' nis_validate(stays)$analysis_ready
#' nis_close(session)
#' unlink(path)
nis_import <- function(session, core, year, hospital = NULL, severity = NULL,
                       diagnosis_procedure_groups = NULL, provenance = list()) {
  check_session(session)
  validate_years(year)
  if (length(year) != 1L || !year %in% 2017:2022) {
    stop("Structural import is limited to year labels 2017 through 2022.", call. = FALSE)
  }
  if (!is.list(provenance) || (length(provenance) &&
      (is.null(names(provenance)) || anyNA(names(provenance)) ||
       any(!nzchar(names(provenance))) || anyDuplicated(names(provenance))))) {
    stop("`provenance` must be a named list with unique names.", call. = FALSE)
  }
  con <- session$connection
  components <- list(core = core, hospital = hospital, severity = severity,
                     diagnosis_procedure_groups = diagnosis_procedure_groups)
  components <- components[!vapply(components, is.null, logical(1))]
  if (!"core" %in% names(components)) stop("`core` must be supplied.", call. = FALSE)
  created <- character()
  success <- FALSE
  on.exit({
    if (!success && DBI::dbIsValid(con)) {
      for (view in rev(created)) {
        DBI::dbExecute(con, paste("DROP VIEW IF EXISTS", sql_name(con, view)))
      }
    }
  }, add = TRUE)
  sources <- schemas <- views <- list()
  for (component in names(components)) {
    files <- parquet_files(components[[component]])
    schema <- parquet_component_schema(con, files, component)
    view <- next_view_name(session)
    literals <- paste(DBI::dbQuoteString(con, files), collapse = ", ")
    DBI::dbExecute(con, paste0("CREATE TEMP VIEW ", sql_name(con, view),
                              " AS SELECT * FROM read_parquet([", literals,
                              "], union_by_name = false, hive_partitioning = false)"))
    created <- c(created, view)
    views[[component]] <- view
    schemas[[component]] <- schema
    require_fields(schema, "YEAR", component)
    invalid_year <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ",
      sql_name(con, view), " WHERE TRY_CAST(\"YEAR\" AS DOUBLE) IS NULL OR ",
      "TRY_CAST(\"YEAR\" AS DOUBLE) IS DISTINCT FROM ", as.integer(year)))
    if (invalid_year > 0) {
      stop_structure_issue("invalid_year", component, "YEAR", invalid_year,
        paste0(component, " contains missing, invalid, or mixed YEAR values."))
    }
    info <- file.info(files)
    sources[[component]] <- data.frame(
      path = files, bytes = info$size, modified = as.numeric(info$mtime),
      stringsAsFactors = FALSE
    )
  }
  joined <- views$core
  raw_schema <- schemas$core
  joins <- list()
  if (length(views) > 1L) {
    require_unique_keys(con, joined, raw_schema, c("YEAR", "KEY_NIS"), "core")
  }
  for (component in setdiff(names(views), "core")) {
    right <- views[[component]]
    right_schema <- schemas[[component]]
    keys <- c("YEAR", if (component == "hospital") "HOSP_NIS" else "KEY_NIS")
    require_fields(raw_schema, keys, "core")
    require_unique_keys(con, right, right_schema, keys, component)
    left_types <- raw_schema$column_type[match(keys, raw_schema$column_name)]
    right_types <- right_schema$column_type[match(keys, right_schema$column_name)]
    if (!identical(left_types, right_types)) {
      stop_structure_issue("join_key_type", component, keys[left_types != right_types],
        message = paste0("Join key types differ between core and ", component,
                          "; supply a reviewed conversion before joining."))
    }
    left <- sql_name(con, joined)
    right_sql <- sql_name(con, right)
    key_sql <- sql_name(con, keys)
    condition <- paste(paste0("l.", key_sql, " = r.", key_sql), collapse = " AND ")
    unmatched <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", left,
      " l WHERE NOT EXISTS (SELECT 1 FROM ", right_sql, " r WHERE ", condition, ")"))
    if (unmatched > 0) {
      stop_structure_issue("unmatched_core", component, keys, unmatched,
        paste0(component, " has ", unmatched, " unmatched core rows."))
    }
    unused <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", right_sql,
      " r WHERE NOT EXISTS (SELECT 1 FROM ", left, " l WHERE ", condition, ")"))
    shared <- setdiff(intersect(raw_schema$column_name, right_schema$column_name), keys)
    if (length(shared)) {
      same_types <- raw_schema$column_type[match(shared, raw_schema$column_name)] ==
        right_schema$column_type[match(shared, right_schema$column_name)]
      if (!all(same_types)) {
        stop_structure_issue("shared_field_type", component, shared[!same_types],
          message = paste0("Shared columns have different types in ", component, "."))
      }
      conflict <- paste(paste0("l.", sql_name(con, shared), " IS DISTINCT FROM r.",
                               sql_name(con, shared)), collapse = " OR ")
      conflicts <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", left,
        " l JOIN ", right_sql, " r ON ", condition, " WHERE ", conflict))
      if (conflicts > 0) {
        stop_structure_issue("shared_field_conflict", component, shared, conflicts,
          paste0(component, " conflicts with core/shared fields on ", conflicts,
                 " matched rows."))
      }
    }
    additional <- setdiff(right_schema$column_name, raw_schema$column_name)
    cross_case <- tolower(additional) %in% tolower(raw_schema$column_name)
    if (any(cross_case)) {
      stop_structure_issue("field_name_collision", component, additional[cross_case],
        message = "Case-insensitive field collision across components.")
    }
    projection <- if (length(additional)) {
      c("l.*", paste0("r.", sql_name(con, additional)))
    } else "l.*"
    view <- next_view_name(session)
    DBI::dbExecute(con, paste0("CREATE TEMP VIEW ", sql_name(con, view), " AS SELECT ",
      paste(projection, collapse = ", "), " FROM ", left, " l LEFT JOIN ", right_sql,
      " r ON ", condition))
    created <- c(created, view)
    joined <- view
    raw_schema <- rbind(raw_schema, right_schema[right_schema$column_name %in% additional,
                                               , drop = FALSE])
    joins[[component]] <- list(keys = keys, unmatched_core = unmatched,
                               unused_component = unused, shared_columns = shared)
  }
  result <- structure(list(
    session = session, view = joined, year = as.integer(year), schema = raw_schema,
    sources = sources, component_schemas = schemas, joins = joins,
    provenance = provenance, validation_scope = "experimental_structure_only"
  ), class = "nis_data")
  success <- TRUE
  result
}

parquet_files <- function(paths) {
  if (!is.character(paths) || !length(paths) || anyNA(paths) || any(!nzchar(paths))) {
    stop("Parquet input must be local file paths or one directory.", call. = FALSE)
  }
  if (length(paths) == 1L && dir.exists(paths)) {
    paths <- sort(list.files(paths, pattern = "[.]parquet$", recursive = TRUE,
                             full.names = TRUE, ignore.case = TRUE))
  }
  if (!length(paths) || any(!file.exists(paths)) || any(dir.exists(paths)) ||
      any(!grepl("[.]parquet$", paths, ignore.case = TRUE))) {
    stop("Parquet input contains missing files or is an empty/invalid directory.",
         call. = FALSE)
  }
  paths <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  if (anyDuplicated(paths)) stop("Repeated parquet file paths are not allowed.", call. = FALSE)
  paths
}

parquet_component_schema <- function(con, files, component) {
  schemas <- lapply(files, function(path) {
    quoted <- as.character(DBI::dbQuoteString(con, path))
    physical <- DBI::dbGetQuery(con, paste0("SELECT name, num_children FROM parquet_schema(",
                                           quoted, ")"))[-1L, , drop = FALSE]
    if (any(physical$num_children > 0L, na.rm = TRUE)) {
      stop_structure_issue("nested_field", component,
        physical$name[!is.na(physical$num_children) & physical$num_children > 0L],
        message = "Nested parquet fields are not supported by structural import.")
    }
    if (anyDuplicated(tolower(physical$name))) {
      collisions <- duplicated(tolower(physical$name)) |
        duplicated(tolower(physical$name), fromLast = TRUE)
      stop_structure_issue("field_name_collision", component, physical$name[collisions],
        message = "Parquet has case-insensitive field collisions.")
    }
    DBI::dbGetQuery(con, paste0("DESCRIBE SELECT * FROM read_parquet(", quoted,
                              ", hive_partitioning = false)"))[, c("column_name", "column_type")]
  })
  if (!all(vapply(schemas, identical, logical(1), schemas[[1L]]))) {
    stop_structure_issue("shard_schema_mismatch", component,
      unique(unlist(lapply(schemas, function(schema) schema$column_name))),
      message = "Parquet shards must have identical names, column order, and types.")
  }
  schemas[[1L]]
}

require_fields <- function(schema, fields, component) {
  missing <- setdiff(fields, schema$column_name)
  if (length(missing)) {
    stop_structure_issue("required_field_absent", component, missing,
      message = paste0(component, " lacks required fields: ",
                       paste(missing, collapse = ", "), "."))
  }
}

require_unique_keys <- function(con, view, schema, keys, component) {
  require_fields(schema, keys, component)
  quoted <- sql_name(con, keys)
  missing <- paste(paste0(quoted, " IS NULL OR TRIM(CAST(", quoted,
                          " AS VARCHAR)) = ''"), collapse = " OR ")
  missing_count <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ",
                                         sql_name(con, view), " WHERE ", missing))
  if (missing_count > 0) {
    stop_structure_issue("missing_join_keys", component, keys, missing_count,
      paste0(component, " has ", missing_count, " rows with missing join keys."))
  }
  for (key in setdiff(keys, "YEAR")) {
    type <- schema$column_type[match(key, schema$column_name)]
    invalid_count <- identifier_problem_count(con, view, key, type)
    if (invalid_count > 0) {
      stop_structure_issue("invalid_identifier", component, key, invalid_count,
        paste0(component, " has ", invalid_count,
               " invalid or precision-unsafe join identifiers."))
    }
  }
  duplicates <- query_count(con, paste0("SELECT COUNT(*) AS n FROM (SELECT ",
    paste(quoted, collapse = ", "), " FROM ", sql_name(con, view), " GROUP BY ",
    paste(quoted, collapse = ", "), " HAVING COUNT(*) > 1) duplicate_keys"))
  if (duplicates > 0) {
    stop_structure_issue("duplicate_join_keys", component, keys, duplicates,
      paste0(component, " has ", duplicates, " groups of duplicate join keys."))
  }
}

stop_structure_issue <- function(check, component, fields, affected = NA_real_, message) {
  stop(structure(list(message = message, call = NULL, check = check,
                      component = component, fields = fields, affected = affected),
                 class = c("nis_structure_error", "error", "condition")))
}

query_count <- function(con, sql) as.numeric(DBI::dbGetQuery(con, sql)$n)

check_relation <- function(data) {
  if (!inherits(data, "nis_data")) stop("`data` must come from nis_import().", call. = FALSE)
  check_session(data$session)
  for (source in data$sources) {
    current <- file.info(source$path)
    if (anyNA(current$size) || !identical(current$size, source$bytes) ||
        !identical(as.numeric(current$mtime), source$modified)) {
      stop("A parquet source changed or disappeared. Reimport before continuing.",
           call. = FALSE)
    }
  }
  invisible(data)
}

#' Collect an explicit projection from a lazy relation
#'
#' @param data A relation returned by [nis_import()].
#' @param columns A non-empty character vector of exact raw column names.
#' @param limit Optional nonnegative whole row limit. `NULL` collects all rows
#'   for the requested columns. Row order is unspecified.
#' @return A data frame preserving source types, including integer64 identifiers
#'   for BIGINT fields. No fields are implicitly harmonized or recoded.
#'   Identifier fields stored as decimal, floating, or wider integer types are
#'   refused when collection could round their values. Use a reviewed exact
#'   string or signed BIGINT conversion for such identifiers.
#' @export
nis_collect <- function(data, columns, limit = NULL) {
  check_relation(data)
  if (!is.character(columns) || !length(columns) || anyNA(columns) ||
      any(!nzchar(columns)) || anyDuplicated(columns)) {
    stop("`columns` must be unique non-empty raw column names.", call. = FALSE)
  }
  require_fields(data$schema, columns, "relation")
  if (!is.null(limit) && (!(is.integer(limit) || is.double(limit)) ||
      length(limit) != 1L || is.na(limit) || !is.finite(limit) ||
      limit < 0 || limit != floor(limit) || limit > .Machine$integer.max)) {
    stop("`limit` must be one nonnegative whole number up to the R integer limit.",
         call. = FALSE)
  }
  con <- data$session$connection
  for (field in intersect(columns, c("KEY_NIS", "HOSP_NIS", "NIS_STRATUM"))) {
    threshold <- identifier_precision_limit(data$schema$column_type[
      match(field, data$schema$column_name)])
    if (!is.null(threshold)) {
      unsafe <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ",
        sql_name(con, data$view), " WHERE ", sql_name(con, field), " >= ", threshold,
        " OR ", sql_name(con, field), " <= -", threshold))
      if (unsafe > 0) {
        stop("Collection would round precision-unsafe identifiers in ", field,
             "; use a reviewed exact conversion.", call. = FALSE)
      }
    }
  }
  sql <- paste0("SELECT ", paste(sql_name(con, columns), collapse = ", "),
                " FROM ", sql_name(con, data$view))
  if (!is.null(limit)) sql <- paste(sql, "LIMIT", as.integer(limit))
  DBI::dbGetQuery(con, sql)
}
