#' Add CCSR categories to a NIS query
#'
#' Add Clinical Classifications Software Refined categories to a DuckDB query.
#'
#' @details Matches full ICD-10 codes. The any-position and principal modes
#' return distinct categories as a list. The diagnosis default mode returns
#' one inpatient principal diagnosis category.
#'
#' The bundled 2025.1 mappings cover Q4 2015 and calendar years 2016 through
#' 2024. Pin a version to use the same categories across years. Out-of-coverage
#' discharges receive missing results. Within coverage, unmatched discharges
#' receive an empty list or a missing default category.
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
#' @seealso [Define and save a cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html),
#'   [nis_ccsr_codes()], [AHRQ HCUP CCSR](https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp).
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
  if (!nis_is_duckdb(.data)) {
    cli::cli_abort("`.data` must be a lazy DuckDB query.", call = call)
  }
  con <- dbplyr::remote_con(.data)
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
  nis_sql_mutate(.data, sql, c(columns, name))
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
  nis_parquet_scan(con, path)
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
  con <- NULL
  on.exit(if (!is.null(con)) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  suspendInterrupts({
    con <- nis_duckdb_connect(config = list(threads = "1"))
  })
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
  transition_year <- .nis_icd_transition_year
  transition_quarter <- .nis_icd_transition_quarters$icd10
  version_field <- paste0(toupper(type), "VER")
  version_ok <- if (version_field %in% columns) {
    field <- paste0("n.", DBI::dbQuoteIdentifier(con, version_field))
    paste0(" AND (", field, " IS NULL OR TRY_CAST(", field, " AS DOUBLE) = 10)")
  }
  eligible <- paste0(
    year,
    " >= ",
    transition_year,
    " AND ",
    year,
    " = floor(",
    year,
    ")",
    " AND (",
    year,
    " > ",
    transition_year,
    " OR ",
    quarter,
    " IS NULL OR ",
    quarter,
    " = ",
    transition_quarter,
    ")",
    version_ok
  )
  fiscal_year <- as.integer(substr(releases$version, 1L, 4L))
  candidates <- which(!duplicated(fiscal_year))
  candidates <- candidates[order(fiscal_year[candidates])]
  coverage <- paste(year, "<", fiscal_year[candidates])
  if (pinned) {
    coverage <- paste0("(", coverage, " OR (", year, " = ", fiscal_year, " AND ", quarter, " IN (1, 2, 3)))")
  }
  clauses <- paste0("WHEN ", coverage, " THEN ", DBI::dbQuoteString(con, releases$version[candidates]))
  paste("CASE WHEN", eligible, "THEN CASE", paste(clauses, collapse = " "), "END END")
}

ccsr_mapping_joins <- function(con, slots, aliases, rule) {
  paste0(
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
}

ccsr_query_sql <- function(data, con, columns, slots, type, position, releases, version, categories, name) {
  input <- dbplyr::sql_render(data)
  output <- DBI::dbQuoteIdentifier(con, name)
  rule <- ccsr_release_sql(con, columns, type, releases, pinned = !is.null(version))
  filter <- ccsr_mapping_filter(con, type, releases$version, categories)
  mapping <- ccsr_reference_sql(con, "map")
  if (position == "any" && length(slots) > 1L && !is.null(categories)) {
    return(ccsr_presence_sql(con, input, output, rule, mapping, filter, slots))
  }
  aliases <- paste0("m", seq_along(slots))
  joins <- ccsr_mapping_joins(con, slots, aliases, rule)
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
  # A single join can inline its lookup so DuckDB can prune input columns
  # from the surrounding projection. Wide joins reuse a materialized lookup.
  materialization <- if (length(slots) == 1L) "NOT MATERIALIZED" else "MATERIALIZED"
  paste(
    "WITH mapping AS",
    materialization,
    "(SELECT version, code,",
    aggregate,
    "AS categories",
    "FROM",
    mapping,
    filter,
    "GROUP BY version, code)",
    "SELECT n.*,",
    result,
    "AS",
    output,
    "FROM (",
    input,
    ") n",
    paste(joins, collapse = "\n")
  )
}

ccsr_presence_sql <- function(con, input, output, rule, mapping, filter, slots) {
  codes <- paste0("CAST(n.", DBI::dbQuoteIdentifier(con, slots), " AS VARCHAR)", collapse = ", ")
  paste0(
    "WITH category_codes AS (\n",
    "  SELECT version, category, list(DISTINCT code) AS codes FROM ",
    mapping,
    " ",
    filter,
    "\n",
    "  GROUP BY version, category\n",
    "), lookup AS (\n",
    "  SELECT version, list(struct_pack(category := category, codes := codes) ORDER BY category) AS categories\n",
    "  FROM category_codes GROUP BY version\n",
    ")\n",
    "SELECT n.*, CASE WHEN (",
    rule,
    ") IS NOT NULL THEN coalesce(\n",
    "  list_transform(list_filter(lookup.categories, lambda c: list_has_any([",
    codes,
    "], c.codes)),\n",
    "    lambda c: c.category), []::VARCHAR[]) END AS ",
    output,
    "\n",
    "FROM (",
    input,
    ") n\n",
    "LEFT JOIN lookup ON lookup.version = (",
    rule,
    ")"
  )
}
