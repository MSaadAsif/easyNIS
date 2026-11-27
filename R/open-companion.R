#' Attach an annual NIS companion to Core discharges
#'
#' @param .data A lazy Core query from [nis_open()], including its linkage fields.
#' @param path Directory containing Parquet for one companion component, using
#'   the annual or Hive layout accepted by [nis_open()]. Keep Core and each
#'   companion in separate directories, with parts from the same release.
#' @param component One of `"hospital"`, `"severity"`, or `"dx_pr_grps"`.
#' @param columns <[tidy-select][dplyr::dplyr_tidy_select]> Select one or more
#'   companion fields by name across the selected years. Linkage keys are
#'   included automatically and are outside the selection. Use the field's
#'   source spelling for bare names or `all_of()`. Selected fields keep
#'   their source names and must have names distinct from fields in `.data`.
#'
#' @details Hospital uses `YEAR` and `HOSP_NIS`. Severity and Diagnosis and
#'   Procedure Groups use `YEAR` and `KEY_NIS`. Include companion parts for
#'   every year opened in `.data`. A field supplied only in some of those years
#'   is missing in the others. A discharge without a matching companion row
#'   is retained with missing companion values.
#'
#'   DuckDB checks for missing, duplicate, or incompatible companion keys
#'   before constructing the left join. Uniqueness in the Core key types
#'   guarantees exactly one output row per input discharge. Keep both sets
#'   of Parquet files in place until the lazy query is evaluated.
#'
#'   Use hospital characteristics to describe discharges and compare
#'   discharge outcomes. The joined rows and weights still represent
#'   discharges. The Hospital file's `TOTAL_DISC` counts sampled discharges
#'   and is excluded from this helper. HCUP's post-2011 design does not
#'   support estimating individual hospital volumes.
#'
#' @return A lazy DuckDB-backed Core query with the requested columns added.
#' @seealso [Opening NIS data](../articles/opening-data.html),
#'   [HCUP NIS File Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp).
#' @export
#' @examples
#' path <- tempfile()
#' con <- DBI::dbConnect(duckdb::duckdb())
#' write_component <- function(component, fields) {
#'   folder <- file.path(path, component)
#'   dir.create(folder, recursive = TRUE)
#'   file <- DBI::dbQuoteString(con, file.path(folder, "NIS_2020.parquet"))
#'   DBI::dbExecute(con, paste0("COPY (SELECT ", fields, ") TO ", file, " (FORMAT PARQUET)"))
#' }
#' write_component("core", "2020 AS YEAR, 1 AS KEY_NIS, 7 AS HOSP_NIS")
#' write_component("hospital", "7 AS HOSP_NIS, 2 AS HOSP_BEDSIZE")
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' nis_open(file.path(path, "core"), check_release = FALSE) |>
#'   nis_join_companion(file.path(path, "hospital"), "hospital", nis_vars_hospital()) |>
#'   dplyr::collect()
nis_join_companion <- function(.data, path, component, columns) {
  component <- rlang::arg_match(component, c("hospital", "severity", "dx_pr_grps"))
  if (!inherits(.data, "tbl_sql") || is.null(.data$src$.easyNIS_years)) {
    cli::cli_abort("`.data` must be a lazy Core query from {.fn nis_open}.")
  }
  id <- if (component == "hospital") "HOSP_NIS" else "KEY_NIS"
  fields <- colnames(.data)
  required <- unique(c("YEAR", "KEY_NIS", id))
  core_keys <- nis_companion_fields(required, fields)
  if (anyNA(core_keys)) {
    cli::cli_abort("The Core query must include {.field {required[is.na(core_keys)]}}.")
  }
  con <- dbplyr::remote_con(.data)
  dataset <- nis_open_discover(path, .data$src$.easyNIS_years, rlang::current_call())
  sources <- nis_open_source_paths(.data)
  if (any(dataset$parts$path %in% sources)) {
    cli::cli_abort("Keep Core and each companion in separate Parquet files.")
  }
  keys <- c("YEAR", id)
  companion <- nis_companion_query(dataset$parts, con, id)
  available <- colnames(companion)
  key_fields <- nis_companion_fields(keys, available)
  columns <- nis_select_columns(companion, rlang::enquo(columns), exclude = key_fields)
  nis_companion_check_columns(columns, fields, component)
  companion <- dplyr::select(companion, tidyselect::all_of(c(stats::setNames(key_fields, keys), columns)))
  names(keys) <- core_keys[match(keys, required)]
  companion <- nis_companion_check_keys(.data, companion, keys, con)
  joined <- dplyr::left_join(.data, companion, by = keys, na_matches = "never")
  joined$src$.easyNIS_source_paths <- c(sources, dataset$parts$path)
  joined
}

nis_companion_fields <- function(requested, fields) {
  fields[match(nis_sql_identifier_key(requested), nis_sql_identifier_key(fields))]
}

nis_companion_check_columns <- function(columns, core, component) {
  if (!length(columns)) {
    cli::cli_abort("`columns` must select at least one companion field.", call = rlang::caller_call())
  }
  keys <- nis_sql_identifier_key(columns)
  if (component == "hospital" && "total_disc" %in% keys) {
    cli::cli_abort("{.field TOTAL_DISC} is a sampled discharge count and cannot estimate hospital volume.")
  }
  overlaps <- columns[!is.na(nis_companion_fields(columns, core))]
  if (length(overlaps)) {
    cli::cli_abort("Companion field{?s} {.field {overlaps}} already in the discharge query.")
  }
}

nis_companion_query <- function(parts, con, id) {
  # Annual filenames supply the year just as Hive partitions do.
  parts$partition_year <- parts$year
  plan <- nis_open_plan_parquet(parts, con, "duckdb")
  has_key <- vapply(
    plan$names_by_part,
    function(fields) {
      !is.na(nis_companion_fields(id, fields))
    },
    logical(1)
  )
  if (!all(has_key)) {
    cli::cli_abort("Every companion part must contain {.field {id}}.")
  }
  plan$query
}

nis_companion_check_keys <- function(core, companion, keys, con) {
  describe <- function(query, fields) {
    projection <- dplyr::select(dplyr::ungroup(query), tidyselect::all_of(fields))
    DBI::dbGetQuery(con, paste("DESCRIBE", dbplyr::sql_render(projection)))$column_type
  }
  core_types <- describe(core, names(keys))
  companion_types <- describe(companion, unname(keys))
  if (core_types[[1L]] != "INTEGER") {
    cli::cli_abort("The Core query must retain an integer {.field YEAR}.")
  }

  id <- keys[[2L]]
  quoted <- as.character(DBI::dbQuoteIdentifier(con, unname(keys)))
  # Match the Core type explicitly. DuckDB's implicit join coercions could
  # otherwise let distinct companion keys match the same Core row.
  converted <- paste0("TRY_CAST(", quoted[[2L]], " AS ", core_types[[2L]], ")")
  round_trip <- paste0("TRY_CAST(", converted, " AS ", companion_types[[2L]], ")")
  projection <- dplyr::select(companion, tidyselect::all_of(unname(keys)))
  invalid <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT EXISTS (SELECT 1 FROM (",
      dbplyr::sql_render(projection),
      ") AS companion",
      " GROUP BY ",
      quoted[[1L]],
      ", ",
      converted,
      " HAVING COUNT(*) > 1 OR BOOL_OR(",
      converted,
      " IS NULL OR ",
      round_trip,
      " IS DISTINCT FROM ",
      quoted[[2L]],
      ")) AS invalid"
    )
  )
  if (invalid$invalid[[1L]]) {
    cli::cli_abort(
      "Companion keys {.field YEAR} and {.field {id}} must be unique, non-missing, and compatible with Core.",
      class = "easynis_companion_key"
    )
  }
  dplyr::mutate(companion, !!id := dbplyr::sql(converted))
}
