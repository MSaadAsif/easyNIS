#' Open annual NIS Parquet files lazily
#'
#' Open selected years as a DuckDB query.
#'
#' @details Use annual `NIS_<year>.parquet` files or directories, or Hive
#' directories named `YEAR=YYYY`. Use one layout per year. The package matches
#' columns by name and checks that recorded years agree with their partitions.
#' The charge fields for 2023 and 2024 remain separate from `TOTCHG`.
#'
#' @section Annual release check:
#' For years with published reference totals, the check compares discharges,
#' the sum of weights, and distinct hospitals when the relevant fields are
#' available. Investigate warnings against the annual release documentation.
#' Invented data and extracts created with [nis_write_cohort()] are exempt
#' from comparisons with published totals.
#'
#' @section Reading into R:
#' Select columns and summarize in DuckDB before calling [dplyr::collect()].
#' The default reader rejects malformed UTF-8 when it reads the affected
#' column. Reconvert from a correctly encoded source with [nis_convert()].
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open, 2012 or later. Defaults to every
#'   matching year with Parquet parts. Explicitly requested years must each
#'   have Parquet parts. Years before 2016 are experimental: they hold ICD-9-CM
#'   codes in `DX*`/`PR*` slots, and 2015 holds both systems (see
#'   [nis_flag_dx()]).
#' @param reader Parquet reader: `"duckdb"` (default) or `"arrow"`. Arrow is
#'   an optional dependency. Its reader preserves source bytes in strings,
#'   including malformed UTF-8, and allocates memory outside DuckDB's buffer limit.
#' @param check_release Check annual release totals and design fields by
#'   default. Set to `FALSE` to skip the check.
#'
#' @return A lazy DuckDB-backed dbplyr table. Annual source column names are
#'   case-normalized. Saved cohorts retain the column names used at export.
#' @family data-access
#' @seealso [Prepare annual NIS files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html).
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
  release <- if (check_release) nis_open_check_release(plan, dataset) else "skipped"
  paths <- unique(dataset$parts$path)
  definitions <- nis_cohort_definitions(connection$con, paths)
  query <- plan$query
  if (anyNA(definitions) || length(definitions) != length(paths)) {
    query <- nis_open_normalize_names(query, unlist(plan$names_by_part, use.names = FALSE))
  }
  nis_open_warn_2023(query)
  if (reader == "duckdb") {
    collect <- attr(connection$con, "easyNIS_collect")
    collect$source <- as.character(dbplyr::sql_render(query))
  }
  query$src$.easyNIS_source_paths <- paths
  query$src$.easyNIS_cohort_definitions <- definitions
  query$src$.easyNIS_years <- dataset$years
  query$src$.easyNIS_release_check <- release
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
