#' Add CCSR categories to a NIS query
#'
#' Matches complete ICD-10 codes in DuckDB and preserves one row per input
#' row. The `"any"` and `"principal"` positions produce a list column of
#' distinct, sorted categories. For inpatient diagnoses, `"default"` produces
#' the single HCUP default category for `I10_DX1`.
#'
#' AHRQ's CCSR mappings are cumulative from October 2015. For each discharge
#' year, the default is the earliest bundled fiscal year covering that entire
#' calendar year, using the latest bundled revision of that fiscal year.
#' The bundled DXCCSR and PRCCSR v2025.1 cover Q4 2015 and 2016–2024 by this
#' rule. Pinning `"2025.1"` also covers Q1–Q3 2025 when `DQTR` is available.
#' A fixed version can keep category definitions constant across years.
#'
#' ICD-9 discharges and rows outside the selected release's coverage get
#' missing results. Within coverage, a row without any matching codes gets
#' an empty list, or `NA` for its inpatient default category. Match results
#' use the release as published and do not establish whether an individual
#' code was valid on a specific discharge date.
#'
#' @param .data Lazy DuckDB query with `YEAR` and canonical `I10_DX<n>` or
#'   `I10_PR<n>` slots. When present, `DQTR` identifies Q4 2015 and
#'   `DXVER` or `PRVER` must be 10 or missing for ICD-10 records.
#' @param categories Optional character vector of CCSR category codes, such
#'   as `"CIR019"`, to keep. The default returns all assigned categories.
#' @param type `"dx"` for diagnoses or `"pr"` for procedures.
#' @param position `"any"` checks all slots, `"principal"` checks slot 1,
#'   and `"default"` returns the inpatient principal diagnosis default.
#' @param version Optional bundled version, such as `"2025.1"`, to use
#'   across years.
#' @param name Name of the new column.
#' @return A lazy DuckDB query with one additional column.
#' @seealso [nis_ccsr_codes()], [AHRQ HCUP CCSR](https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp).
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020))
#' nis |>
#'   nis_add_ccsr(position = "default") |>
#'   dplyr::count(ccsr) |>
#'   dplyr::collect()
#' @export
nis_add_ccsr <- function(
  .data,
  categories = NULL,
  type = c("dx", "pr"),
  position = c("any", "principal", "default"),
  version = NULL,
  name = "ccsr"
) {
  call <- rlang::current_call()
  type <- match.arg(type)
  position <- match.arg(position)
  con <- ccsr_query_connection(.data, call)
  columns <- nis_names(.data)
  ccsr_validate_output(.data, columns, name, type, position, call)
  slots <- nis_flag_slot_names(columns, toupper(type), "icd10", if (position == "default") "principal" else position)
  releases <- ccsr_releases(type, version, call)
  if (!is.null(categories)) {
    categories <- validate_ccsr_categories(categories, call)
    category_table <- ccsr_reference_sql(con, "categories")
    available <- DBI::dbGetQuery(
      con,
      paste("SELECT DISTINCT category FROM", category_table, ccsr_mapping_filter(con, type, releases$version))
    )$category
    validate_ccsr_category_names(categories, available, call, source = "bundled releases")
  }
  sql <- ccsr_query_sql(.data, con, columns, slots, type, position, releases, version, categories, name)
  out <- dplyr::tbl(con, dbplyr::sql(sql), vars = c(columns, name))
  out$src <- .data$src
  if (inherits(.data, "tbl_nis")) {
    class(out) <- c("tbl_nis", class(out))
  }
  dplyr::group_by(out, !!!rlang::syms(dplyr::group_vars(.data)))
}

ccsr_reference_dir <- function() {
  system.file("ccsr", package = "easyNIS", mustWork = TRUE)
}

ccsr_releases <- function(type, version, call) {
  releases <- utils::read.csv(file.path(ccsr_reference_dir(), "releases.csv"), colClasses = "character")
  releases <- releases[releases$type == type, , drop = FALSE]
  releases <- releases[order(numeric_version(releases$version), decreasing = TRUE), , drop = FALSE]
  if (!is.null(version)) {
    if (!is.character(version) || length(version) != 1L || !version %in% releases$version) {
      cli::cli_abort("CCSR version {.val {version}} is unavailable for {.val {type}}.", call = call)
    }
    releases <- releases[releases$version == version, , drop = FALSE]
  }
  releases
}

ccsr_query_connection <- function(data, call) {
  if (inherits(data, "tbl_sql")) {
    con <- dbplyr::remote_con(data)
    if (inherits(con, "duckdb_connection")) {
      return(con)
    }
  }
  cli::cli_abort("`.data` must be a lazy DuckDB query.", call = call)
}

ccsr_validate_output <- function(data, columns, name, type, position, call) {
  if (!"YEAR" %in% columns) {
    cli::cli_abort("`.data` must contain `YEAR` to select a CCSR release.", call = call)
  }
  if (type == "pr" && position == "default") {
    cli::cli_abort("Procedure categories have no principal diagnosis default.", call = call)
  }
  if (
    !rlang::is_string(name) ||
      !nzchar(name) ||
      !identical(name, nis_internal_names(data, columns, name))
  ) {
    cli::cli_abort("`name` must be a new, non-empty column name.", call = call)
  }
}

ccsr_reference_sql <- function(con, table) {
  path <- file.path(ccsr_reference_dir(), paste0(table, ".parquet"))
  paste0("read_parquet(", DBI::dbQuoteString(con, path), ")")
}

ccsr_mapping_filter <- function(con, type, versions, categories = NULL) {
  sql <- paste0(
    "WHERE type = ",
    DBI::dbQuoteString(con, type),
    " AND version IN (",
    paste(DBI::dbQuoteString(con, versions), collapse = ", "),
    ")"
  )
  if (!is.null(categories)) {
    sql <- paste0(sql, " AND category IN (", paste(DBI::dbQuoteString(con, categories), collapse = ", "), ")")
  }
  sql
}

ccsr_bundled_codes <- function(categories, default_only, type, version, call) {
  if (default_only && type == "pr") {
    cli::cli_abort("Procedure categories have no default assignment.", call = call)
  }
  release <- ccsr_releases(type, version, call)$version[1L]
  con <- nis_duckdb_connect(config = list(threads = "1"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  available <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT category FROM",
      ccsr_reference_sql(con, "categories"),
      ccsr_mapping_filter(con, type, release)
    )
  )$category
  validate_ccsr_category_names(categories, available, call, source = "bundled release")
  DBI::dbGetQuery(
    con,
    paste(
      "SELECT DISTINCT code FROM",
      ccsr_reference_sql(con, "map"),
      ccsr_mapping_filter(con, type, release, categories),
      if (default_only) "AND inpatient = 'Y'" else "",
      "ORDER BY code"
    )
  )$code
}

ccsr_release_sql <- function(con, columns, type, releases, pinned) {
  year <- 'TRY_CAST(n."YEAR" AS DOUBLE)'
  quarter <- if ("DQTR" %in% columns) 'TRY_CAST(n."DQTR" AS DOUBLE)' else "NULL"
  version_field <- paste0(toupper(type), "VER")
  version_ok <- if (version_field %in% columns) {
    field <- paste0("n.", DBI::dbQuoteIdentifier(con, version_field))
    paste0(" AND (", field, " IS NULL OR TRY_CAST(", field, " AS DOUBLE) = 10)")
  }
  eligible <- paste0(
    year,
    " >= 2015 AND ",
    year,
    " = floor(",
    year,
    ")",
    " AND (",
    year,
    " > 2015 OR ",
    quarter,
    " IS NULL OR ",
    quarter,
    " = 4)",
    version_ok
  )
  fiscal_year <- as.integer(substr(releases$version, 1L, 4L))
  # Retain the latest revision in each fiscal year, then try years in order.
  candidates <- which(!duplicated(fiscal_year))
  candidates <- candidates[order(fiscal_year[candidates])]
  coverage <- paste(year, "<", fiscal_year[candidates])
  if (pinned) {
    coverage <- paste0("(", coverage, " OR (", year, " = ", fiscal_year, " AND ", quarter, " IN (1, 2, 3)))")
  }
  clauses <- paste0("WHEN ", coverage, " THEN ", DBI::dbQuoteString(con, releases$version[candidates]))
  paste("CASE WHEN", eligible, "THEN CASE", paste(clauses, collapse = " "), "END END")
}

ccsr_query_sql <- function(data, con, columns, slots, type, position, releases, version, categories, name) {
  rule <- ccsr_release_sql(con, columns, type, releases, pinned = !is.null(version))
  filter <- ccsr_mapping_filter(con, type, releases$version, categories)
  aliases <- paste0("m", seq_along(slots))
  joins <- paste0(
    "LEFT JOIN mapping ",
    aliases,
    " ON ",
    aliases,
    ".version = (",
    rule,
    ") AND ",
    aliases,
    ".code = CAST(n.",
    DBI::dbQuoteIdentifier(con, slots),
    " AS VARCHAR)"
  )
  values <- paste0(aliases, ".categories")
  if (position == "default") {
    aggregate <- "min(category)"
    filter <- paste(filter, "AND inpatient = 'Y'")
    result <- values
  } else {
    aggregate <- "list(category)"
    result <- paste0(
      "CASE WHEN (",
      rule,
      ") IS NOT NULL THEN list_sort(list_distinct(list_concat(",
      paste(values, collapse = ", "),
      "))) END"
    )
  }
  paste(
    "WITH mapping AS MATERIALIZED (SELECT version, code,",
    aggregate,
    "AS categories",
    "FROM",
    ccsr_reference_sql(con, "map"),
    filter,
    "GROUP BY version, code)",
    "SELECT n.*,",
    result,
    "AS",
    DBI::dbQuoteIdentifier(con, name),
    "FROM (",
    dbplyr::sql_render(data),
    ") n",
    paste(joins, collapse = "\n")
  )
}
