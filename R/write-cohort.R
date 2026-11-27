#' Save a reusable NIS cohort
#'
#' Write cohort discharges and one zero-domain placeholder for each sampled
#' hospital-year without a cohort discharge. Open the resulting directory with
#' [nis_open()] and omit `cohort` in [nis_design()]. To narrow the cohort,
#' filter the resulting survey design so its sampled hospitals stay in scope.
#'
#' The output is a directory of yearly Zstandard-compressed Parquet parts.
#' Each part records the cohort expression, the years opened by the source
#' query, and the easyNIS version in its Parquet metadata. The expression is
#' recorded as supplied, so also retain the code that defines any flags or
#' variables it uses. The release check exempts the extract from comparison
#' against HCUP release totals.
#'
#' @param .data A lazy query from [nis_open()], with any cohort flags added.
#'   Include the whole sample for the years you intend to analyze.
#' @param cohort Logical data-masked cohort expression. Missing values are
#'   outside the cohort. Omit when re-saving a dataset written by this function.
#' @param path A new output directory in an existing parent directory.
#' @param keep Tidyselect expression or character vector of analysis columns
#'   to write. Rename columns on the query before exporting. `YEAR`,
#'   `HOSP_NIS`, `NIS_STRATUM`, and `DISCWT` are always written.
#'
#' @return The original `path`, invisibly. If collecting raw rows directly
#'   from the saved dataset, filter on `.in_cohort` to count only discharges.
#' @export
#' @seealso [nis_design()], [Defining cohorts](articles/cohorts.html).
#' @examples
#' query <- nis_open(nis_example(years = 2019))
#' path <- nis_write_cohort(query, AGE >= 65, tempfile(), keep = LOS)
#' design <- nis_design(nis_open(path), keep = LOS)
#' dplyr::summarise(design, discharges = srvyr::survey_total())
nis_write_cohort <- function(.data, cohort, path, keep) {
  call <- rlang::current_call()
  if (!inherits(.data, "tbl_sql") || is.null(nis_open_source_paths(.data))) {
    cli::cli_abort("`.data` must be a lazy query from `nis_open()`.", call = call)
  }
  if (!rlang::is_string(path) || !nzchar(path) || !dir.exists(dirname(path))) {
    cli::cli_abort("`path` must name a new directory in an existing parent directory.", call = call)
  }
  target <- file.path(normalizePath(dirname(path), winslash = "/", mustWork = TRUE), basename(path))
  nis_convert_check_target(target)

  query <- dplyr::ungroup(.data)
  previous_definition <- nis_saved_cohort(query, call)
  saved <- !is.null(previous_definition)
  membership <- nis_cohort_membership(rlang::enquo(cohort), saved, call)
  nis_design_validate(query, "TOTCHG", FALSE, call, saved)
  fields <- nis_design_fields(query, rlang::enquo(keep), call)
  if (!identical(names(fields$keep_map), unname(fields$keep_map)) && length(fields$keep_map)) {
    cli::cli_abort("`keep` cannot rename columns. Use `dplyr::rename()` before exporting.", call = call)
  }

  temp <- tempfile(".easynis-cohort-", tmpdir = dirname(target))
  if (!dir.create(temp, mode = "0700")) {
    cli::cli_abort("Could not create a temporary sibling of {.path {target}}.", call = call)
  }
  temp <- normalizePath(temp, winslash = "/", mustWork = TRUE)
  on.exit(nis_remove_owned_directory(temp), add = TRUE)
  stage <- list(temp = temp, target = target)
  metadata <- c(
    nis_non_release_metadata,
    easyNIS_cohort = if (saved) {
      previous_definition
    } else {
      paste(rlang::expr_deparse(rlang::get_expr(membership)), collapse = "\n")
    },
    easyNIS_source_years = paste(sort(query$src$.easyNIS_years), collapse = ","),
    easyNIS_version = as.character(utils::packageVersion("easyNIS"))
  )
  count <- nis_cohort_copy(query, membership, fields$selected, temp, metadata, call)
  nis_cohort_check_count(temp, count, call)
  nis_convert_publish(stage)
  invisible(path)
}

nis_cohort_membership <- function(cohort, saved, call) {
  missing <- rlang::quo_is_missing(cohort)
  if (saved && !missing) {
    cli::cli_abort("Omit `cohort` when using a saved cohort.", call = call)
  }
  if (saved) {
    return(rlang::quo(.in_cohort))
  }
  if (missing) {
    cli::cli_abort("Supply a `cohort` expression for the source sample.", call = call)
  }
  nis_design_cohort_expr(cohort, call)
}

nis_saved_cohort <- function(query, call) {
  if (!inherits(query, "tbl_sql")) {
    return(NULL)
  }
  definitions <- query$src$.easyNIS_cohort_definitions
  if (!length(definitions)) {
    return(NULL)
  }
  paths <- nis_open_source_paths(query)
  if (length(definitions) != length(paths) || anyNA(definitions) || length(unique(definitions)) != 1L) {
    cli::cli_abort("Open a saved cohort separately from other datasets.", call = call)
  }
  if (!".in_cohort" %in% nis_names(query)) {
    cli::cli_abort("Keep the `.in_cohort` membership column in a saved cohort query.", call = call)
  }
  definitions[[1L]]
}

nis_cohort_definitions <- function(con, paths) {
  # Group by path so duplicate footer entries cannot mask an unmarked part.
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT CASE WHEN count(*) = 1 THEN first(value::VARCHAR) END AS definition FROM parquet_kv_metadata(",
      nis_parquet_paths(con, paths),
      ") WHERE key = 'easyNIS_cohort'::BLOB GROUP BY file_name"
    )
  )$definition
}

nis_cohort_copy <- function(query, membership, selected, temp, metadata, call) {
  con <- dbplyr::remote_con(query)
  flush <- DBI::dbGetQuery(
    con,
    "SELECT current_setting('partitioned_write_flush_threshold') AS threshold"
  )$threshold
  if (flush > 16384) {
    # Partitioned COPY buffers input on each worker before writing row groups.
    DBI::dbExecute(con, "SET partitioned_write_flush_threshold = 16384")
    on.exit(DBI::dbExecute(con, paste("SET partitioned_write_flush_threshold =", flush)), add = TRUE)
  }
  prepared <- nis_sample_fields(nis_design_input(query), membership)
  patients <- prepared |>
    nis_design_cohort_type(call) |>
    dplyr::filter(.nis_valid, .nis_cohort) |>
    dplyr::select(dplyr::all_of(selected))
  hospitals <- prepared |>
    dplyr::filter(.nis_valid) |>
    nis_sample_group_rows(setdiff(.nis_design_fields, "DISCWT")) |>
    dplyr::select(dplyr::all_of(.nis_design_fields))

  # Use the staged patient files to identify represented hospitals. Only
  # those keys need to be read back, and membership is evaluated once.
  patient_sql <- paste0("SELECT *, true AS \".in_cohort\" FROM (", dbplyr::sql_render(patients), ")")
  count <- nis_cohort_copy_parquet(con, patient_sql, temp, metadata)
  files <- list.files(temp, pattern = "\\.parquet$", all.files = TRUE, recursive = TRUE, full.names = TRUE)
  staged <- if (length(files)) nis_parquet_scan(con, files)
  placeholders <- nis_cohort_placeholders(patient_sql, dbplyr::sql_render(hospitals), staged)
  count + nis_cohort_copy_parquet(con, placeholders, temp, metadata)
}

nis_cohort_placeholders <- function(patients, hospitals, staged) {
  keys <- paste(c("YEAR", "HOSP_NIS"), collapse = ", ")
  if (is.null(staged)) {
    schema <- paste0("(", patients, ")")
    anti_join <- ""
  } else {
    schema <- staged
    anti_join <- paste0(" ANTI JOIN (SELECT DISTINCT ", keys, " FROM ", staged, ") USING (", keys, ")")
  }
  # The empty branch gives non-design fields the same types as patient rows.
  paste0(
    "WITH hospitals AS MATERIALIZED (",
    hospitals,
    ") ",
    "SELECT * FROM ",
    schema,
    " WHERE false UNION ALL BY NAME ",
    "SELECT h.*, false AS \".in_cohort\" FROM hospitals h",
    anti_join,
    " ",
    "WHERE (SELECT CASE WHEN count(*) = count(DISTINCT (",
    keys,
    ")) THEN true ",
    "ELSE error('Each hospital must map to one stratum within a year.') END FROM hospitals)"
  )
}

nis_cohort_copy_parquet <- function(con, sql, temp, metadata) {
  destination <- DBI::dbQuoteString(con, temp)
  kv <- paste(DBI::dbQuoteIdentifier(con, names(metadata)), DBI::dbQuoteString(con, unname(metadata)), sep = ": ")
  statement <- paste0(
    "COPY (SELECT *, YEAR AS \".nis_cohort_year\" FROM (",
    sql,
    ")) ",
    "TO ",
    destination,
    ' (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 32768, APPEND, PARTITION_BY (".nis_cohort_year"), KV_METADATA {',
    paste(kv, collapse = ", "),
    "})"
  )
  nis_duckdb_translate_errors(DBI::dbExecute(con, statement))
}

nis_cohort_check_count <- function(temp, expected, call) {
  if (expected == 0) {
    cli::cli_abort("No discharges have valid design fields.", call = call)
  }
  # nis_open() finds Hive partitions recursively. Annual names keep extracts
  # inside the source root out of the source's scan.
  parts <- list.dirs(temp, full.names = FALSE, recursive = FALSE)
  pattern <- "^\\.nis_cohort_year=([0-9]{4})$"
  if (!length(parts) || !all(grepl(pattern, parts))) {
    cli::cli_abort("The export did not produce valid yearly Parquet partitions.", call = call)
  }
  annual <- sub(pattern, "NIS_\\1.parquet", parts)
  if (!all(file.rename(file.path(temp, parts), file.path(temp, annual)))) {
    cli::cli_abort("Could not name the saved cohort's yearly partitions.", call = call)
  }
  dataset <- nis_open_discover(temp, NULL, call)
  con <- nis_duckdb_connect(config = list(threads = "1"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  count <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT sum(num_rows)::DOUBLE AS n FROM parquet_file_metadata(",
      nis_parquet_paths(con, dataset$parts$path),
      ")"
    )
  )$n
  if (is.na(count) || count != expected) {
    cli::cli_abort("The saved cohort row count does not match the export.", call = call)
  }
}
