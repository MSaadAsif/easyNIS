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
#' against HCUP release totals. Saved cohorts retain the column names used at
#' export, including mixed-case names.
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
#' @family cohort-definition
#' @seealso [nis_design()], [Defining cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).
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
  parent <- normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
  target <- file.path(parent, basename(path))
  nis_check_output_target(target)

  source <- nis_sample_source(.data, rlang::enquo(cohort), call)
  query <- nis_sample_input(source$data, source$saved, call)
  fields <- nis_design_fields(query, rlang::enquo(keep), call)
  if (!identical(names(fields$keep_map), unname(fields$keep_map)) && length(fields$keep_map)) {
    cli::cli_abort("`keep` cannot rename columns. Use `dplyr::rename()` before exporting.", call = call)
  }

  metadata <- c(
    nis_non_release_metadata,
    easyNIS_cohort = if (source$saved) {
      source$definition
    } else {
      paste(rlang::expr_deparse(rlang::get_expr(source$membership)), collapse = "\n")
    },
    easyNIS_source_years = paste(sort(nis_open_source_info(.data)$years), collapse = ","),
    easyNIS_version = as.character(utils::packageVersion("easyNIS"))
  )
  nis_publish_directory(
    target,
    ".easynis-cohort-",
    function(temp) {
      count <- nis_cohort_copy(query, source$membership, fields$selected, temp, metadata, call)
      nis_cohort_check_count(temp, count, call)
    },
    call = call
  )
  invisible(path)
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
  prepared <- nis_sample_fields(query, membership)
  patients <- nis_design_cohort_type(prepared, call)
  patients <- nis_design_cohort_sql(patients, selected)
  hospitals <- nis_cohort_hospitals_sql(prepared)

  # Use the staged patient files to identify represented hospitals. Only
  # those keys need to be read back, and membership is evaluated once.
  patient_sql <- paste0("SELECT *, true AS \".in_cohort\" FROM (", patients, ")")
  count <- nis_cohort_copy_parquet(con, patient_sql, temp, metadata)
  files <- list.files(temp, pattern = "\\.parquet$", all.files = TRUE, recursive = TRUE, full.names = TRUE)
  staged <- if (length(files)) nis_parquet_scan(con, files)
  placeholders <- nis_cohort_placeholders(patient_sql, hospitals, staged)
  count + nis_cohort_copy_parquet(con, placeholders, temp, metadata)
}

nis_cohort_hospitals_sql <- function(prepared) {
  sprintf(
    paste(
      'SELECT "YEAR", "HOSP_NIS", "NIS_STRATUM", min(CAST("DISCWT" AS DOUBLE)) AS "DISCWT"',
      'FROM (%s) AS prepared WHERE ".nis_valid" GROUP BY 1, 2, 3'
    ),
    dbplyr::sql_render(prepared)
  )
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
  con <- NULL
  on.exit(if (!is.null(con)) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  suspendInterrupts({
    con <- nis_duckdb_connect(config = list(threads = "1"))
  })
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
