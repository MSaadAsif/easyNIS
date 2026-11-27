#' Open annual NIS Parquet files lazily
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open, 2012 or later. Defaults to every
#'   matching year with Parquet parts. Explicitly requested years must each
#'   have Parquet parts. Years before 2016 are experimental: they hold ICD-9-CM
#'   codes in `DX*`/`PR*` slots, and 2015 holds both systems (see
#'   [nis_flag_dx()]).
#' @param reader Parquet reader: `"duckdb"` (default) or `"arrow"`. Arrow is
#'   an optional dependency. Its reader preserves source bytes in strings,
#'   including malformed UTF-8; downstream string operations may still fail.
#' @param check_release Check annual release totals and design fields by
#'   default. Set to `FALSE` to skip the check.
#'
#' @details `nis_open()` reads Parquet directly with DuckDB and returns a
#'   DuckDB-backed dbplyr table. It accepts annual `NIS_<year>.parquet` files
#'   or directories and Hive directories named `YEAR=YYYY` containing Parquet
#'   parts. A selected year must not appear in both annual and Hive layouts.
#'   If a part file
#'   has a physical `YEAR` column, its non-missing values must agree with the
#'   directory year; missing or absent physical values use the partition year.
#'   Schemas are combined by column name, including when annual files and Hive
#'   partitions are mixed. DuckDB combines source fields and promotes annual
#'   types. For names DuckDB folds as ASCII case-insensitive identifiers, the
#'   output uses uppercase spelling when any selected source uses uppercase
#'   ASCII letters. Other names retain the established name normalization,
#'   including coalescing Unicode case-normalization collisions. Source
#'   metadata may suggest an additional spelling-only rename; it is applied
#'   only when its target is unique and does not collide with an output name
#'   under DuckDB's identifier rules. When annual
#'   types differ, DuckDB may promote them; for example, an integer field
#'   combined with a character field is returned as character.
#'   When present, `YEAR` is validated and returned as integer;
#'   invalid values identify the offending file in an error. The connection
#'   remains open while the lazy table is in use and closes after it is released.
#'   Use `dplyr::collect()` to return
#'   data to R. Years before 2016 emit an experimental ICD-9 layout notice once
#'   per R session. The `engine` argument was removed entirely; omit it regardless
#'   of the value used in older code.
#'   The default DuckDB reader may fail when scanning malformed UTF-8 in string
#'   columns. Set `reader = "arrow"` to opt in to scanning individual files
#'   through the optional `arrow` package. Arrow preserves the bytes; it does
#'   not detect or repair all invalid text, and downstream string operations
#'   may still fail on malformed values.
#'
#' @section Annual release check:
#' DuckDB checks the discharge count, sum of `DISCWT`, and distinct
#' `HOSP_NIS` count against the
#' [HCUP summary statistics](https://hcup-us.ahrq.gov/db/nation/nis/nissummstats.jsp)
#' for each opened year from 2012 through 2024. Counts must match exactly,
#' and the weight sum can differ by half a discharge plus a small allowance
#' for floating-point arithmetic because HCUP rounds the published weight sum
#' to a whole discharge. Only finite, positive hospital IDs count, and
#' optional totals are compared only when every checked part for a year has the
#' corresponding column. Files created by [nis_example()] are excluded from
#' these totals. They still undergo the integrity checks below.
#' Parquet files with zero discharges across an entire opened year warn.
#' When the fields are present, missing `YEAR`, `YEAR`
#' outside the opened years, and `NIS_STRATUM` values of zero or less warn
#' even for years without published reference totals. If the check cannot
#' run, it warns with the reason. The lazy query remains available for use.
#' Cohort extracts are expected to differ from the published totals. Use
#' `check_release = FALSE` to skip the check for an intentional extract.
#'
#' @section Large data:
#' The query stays in DuckDB until you collect it. Filter, project, and summarize
#' before collecting. A memory check applies to [dplyr::collect()], including
#' `as.data.frame()` on these lazy tables, and to easyNIS helpers that collect
#' DuckDB results. It estimates the size of the result from DuckDB's query plan
#' and the projected column types. It uses a small sample to refine text widths
#' for simple Parquet reads and counts the result rows before denying a collect.
#' Estimates for filtered queries and variable-width
#' columns can be inaccurate, and the check cannot predict DuckDB's working
#' memory or memory used by subsequent R operations.
#' Estimated results from 20% of available physical memory emit a message; at
#' 50% or more the check raises an `easyNIS_collect_too_large` error. If system
#' memory is unavailable, collection proceeds with a one-time notice. Use
#' `options(easyNIS.collect_prudence = FALSE)` to skip the check.
#'
#' Set the named list option `easyNIS.duckdb_config` before
#' opening to tune `memory_limit`, `threads`, `temp_directory`,
#' `max_temp_directory_size`, or `preserve_insertion_order`. The package
#' assigns each query its own spill location under the supplied private
#' directory, or under the R session's temporary directory by default.
#'
#' @return A lazy DuckDB-backed dbplyr table with case-normalized columns.
#'   Experimental 2023
#'   layouts keep `TOTCHG_2023` as its own column and leave `TOTCHG` untouched,
#'   because the 2023 field is HCUP-adjusted for national estimates and is not
#'   comparable to earlier-year charges. Opening a query that contains
#'   `TOTCHG_2023` warns once per session. To use it, pass
#'   `charges = "TOTCHG_2023"` to [nis_design()] or [nis_cost()], or pool
#'   explicitly with `dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG))`.
#'
#'   The 2023 layout facts used here (`TOTCHG_2023`, removed `HOSP_REGION` and
#'   `HOSP_DIVISION`, sequential `NIS_STRATUM`) are UNVERIFIED against official
#'   HCUP 2023 documentation and real 2023 data; none were available for testing.
#' @family data-access
#' @seealso [Opening NIS data](articles/opening-data.html).
#' @export
#' @examples
#' path <- nis_example(years = 2019:2020)
#' nis <- nis_open(path)
#' nis |>
#'   dplyr::count(YEAR) |>
#'   dplyr::collect()
#'
#' # Open one year only
#' nis_open(path, years = 2020) |>
#'   dplyr::count(YEAR) |>
#'   dplyr::collect()
nis_open <- function(path, years = NULL, reader = c("duckdb", "arrow"), check_release = TRUE) {
  reader <- match.arg(reader)
  if (!rlang::is_bool(check_release)) {
    cli::cli_abort("{.arg check_release} must be `TRUE` or `FALSE`.")
  }
  if (reader == "arrow" && !requireNamespace("arrow", quietly = TRUE)) {
    cli::cli_abort("The {.val arrow} reader requires the optional {.pkg arrow} package.")
  }
  error_call <- rlang::current_call()
  dataset <- nis_open_discover(path, years, error_call)
  nis_open_notice(dataset$years)
  connection <- nis_duckdb_open_data()
  on.exit(connection$release(), add = TRUE)
  plan <- nis_open_plan_parquet(dataset$parts, connection$con, reader)
  # Check source columns before name normalization can add unrelated expressions.
  if (check_release) {
    nis_open_check_release(plan, dataset)
  }
  query <- nis_open_normalize_names(plan$query, unlist(plan$names_by_part, use.names = FALSE))
  nis_open_warn_2023(query)
  if (reader == "duckdb") {
    query$src$con@collect_source <- as.character(dbplyr::sql_render(query))
  }
  query$src$.easyNIS_source_paths <- unique(dataset$parts$path)
  query$src$.easyNIS_years <- dataset$years
  result <- nis_duckdb_attach_finalizer(query, connection$release, plan$owners)
  on.exit(NULL, add = FALSE)
  result
}

nis_open_source_paths <- function(query) {
  query$src$.easyNIS_source_paths
}

nis_open_notice <- function(years) {
  if (any(years < 2016L)) {
    cli::cli_inform(
      c(
        "Experimental: years before 2016 store ICD-9-CM codes in {.field DX1}, {.field PR1}, ... slots.",
        i = "Flag them with {.code system = \"icd9\"}; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4) slots."
      ),
      .frequency = "once",
      .frequency_id = "easyNIS_icd9_layout"
    )
  }
  invisible(NULL)
}

nis_open_normalize_names <- function(query, source_names) {
  old_names <- colnames(query)
  new_names <- ifelse(grepl("[A-Z]", old_names), toupper(old_names), old_names)
  name_groups <- split(old_names, new_names)
  output <- nis_open_restore_spelling(names(name_groups), source_names)
  fields <- vapply(name_groups, "[[", character(1), 1L)
  computed <- which(lengths(name_groups) > 1L | grepl("[^ -~]", fields, useBytes = TRUE))

  if (length(computed)) {
    con <- dbplyr::remote_con(query)
    # Use ASCII argument names while retaining the lazy projection so dbplyr
    # can drop unused coalesces before DuckDB binds their types.
    aliases <- nis_internal_names(query, c(old_names, output), paste0(".nis_projection_", seq_along(computed)))
    expressions <- lapply(name_groups[computed], function(group) {
      quoted <- DBI::dbQuoteIdentifier(con, group)
      if (length(quoted) == 1L) {
        return(dbplyr::sql(quoted))
      }
      dbplyr::sql(paste0("COALESCE(", paste(quoted, collapse = ", "), ")"))
    })
    query <- dplyr::mutate(query, !!!stats::setNames(expressions, aliases))
    fields[computed] <- aliases
  }

  # Tidyselect converts spliced argument names to the native encoding.
  selection <- stats::setNames(fields, output)
  dplyr::select(query, tidyselect::all_of(selection))
}

nis_open_restore_spelling <- function(output, source_names) {
  uppercase <- unique(source_names[grepl("[A-Z]", source_names)])
  keys <- nis_sql_identifier_key(uppercase)
  output_keys <- nis_sql_identifier_key(output)
  source <- match(output_keys, keys)
  proposed <- output
  has_source <- !is.na(source)
  proposed[has_source] <- toupper(uppercase[source[has_source]])
  changed <- which(proposed != output)
  target <- nis_sql_identifier_key(proposed[changed])
  collides <- vapply(
    seq_along(changed),
    function(i) {
      target[[i]] %in% output_keys[-changed[[i]]]
    },
    logical(1)
  )
  duplicate <- duplicated(target) | duplicated(target, fromLast = TRUE)
  keep <- changed[!collides & !duplicate]
  output[keep] <- proposed[keep]
  output
}

nis_open_warn_2023 <- function(query) {
  output_names <- colnames(query)
  if ("TOTCHG_2023" %in% output_names) {
    warning_messages <- c(
      paste(
        "This query contains {.field TOTCHG_2023}, which is not comparable",
        "to {.field TOTCHG}."
      ),
      paste(
        "HCUP adjusts it for states missing from 2023, so charges and costs",
        "built from it differ in definition from earlier years."
      ),
      paste(
        "{.fn nis_open} leaves {.field TOTCHG} unchanged; opt in with",
        "{.code charges = \"TOTCHG_2023\"}."
      ),
      paste(
        "The 2023 layout support is experimental and unverified against",
        "real 2023 data."
      )
    )
    names(warning_messages) <- c("", rep("i", length(warning_messages) - 1L))
    cli::cli_warn(
      warning_messages,
      .frequency = "once",
      .frequency_id = "easyNIS_totchg_2023"
    )
  }
  invisible(NULL)
}
