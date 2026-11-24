nis_validate_layout_years <- function(entries, found, years, error_call) {
  paths <- normalizePath(entries, winslash = "/", mustWork = TRUE)
  covered <- vapply(seq_along(entries), function(i) {
    any(startsWith(paths[[i]], paste0(paths[found == found[[i]]], "/")))
  }, logical(1))
  entries <- entries[!covered]
  found <- found[!covered]
  annual <- grepl("^NIS_[0-9]{4}[.]parquet$", basename(entries))
  annual_years <- found[annual]
  hive_years <- found[!annual]
  conflicting_years <- intersect(years, intersect(annual_years, hive_years))
  if (length(conflicting_years) == 0L) return(invisible(NULL))

  details <- vapply(conflicting_years, function(year) {
    annual_path <- entries[annual & found == year]
    hive_path <- entries[!annual & found == year]
    paste0("Year ", year, ": annual ", paste(annual_path, collapse = ", "),
      " and Hive ", paste(hive_path, collapse = ", "))
  }, character(1))
  cli::cli_abort(paste0(
    "A year is present in both annual and Hive layouts.\n",
    paste0("x Year is duplicated: ", details, collapse = "\n"),
    "\ni Keep one layout per year."
  ), call = error_call)
}

#' Open annual NIS Parquet files lazily
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open, 2012 or later. Defaults to every
#'   matching year. Years before 2016 are experimental: they hold ICD-9-CM
#'   codes in `DX*`/`PR*` slots, and 2015 holds both systems (see
#'   [nis_flag_dx()]).
#' @param reader Parquet reader: `"duckdb"` (default) or `"arrow"`. Arrow is
#'   an optional dependency. Its reader preserves source bytes in strings,
#'   including malformed UTF-8; downstream string operations may still fail.
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
#' @section Large data:
#' The query stays in DuckDB until you collect it. Filter, project, and summarize
#' before collecting. Set the named list option `easyNIS.duckdb_config` before
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
nis_open <- function(path, years = NULL, reader = c("duckdb", "arrow")) {
  reader <- match.arg(reader)
  if (reader == "arrow" && !requireNamespace("arrow", quietly = TRUE)) {
    cli::cli_abort("The {.val arrow} reader requires the optional {.pkg arrow} package.")
  }
  error_call <- rlang::current_call()
  selected <- nis_open_select(path, years, error_call)
  nis_open_notice(selected$years)
  sources <- nis_open_sources(selected, error_call)
  connection <- nis_duckdb_open_data()
  on.exit(connection$release(), add = TRUE)
  con <- connection$con
  sources <- Map(nis_open_scan, sources$path, sources$partition_year, seq_len(nrow(sources)),
    MoreArgs = list(con = con, reader = reader))
  lapply(sources, nis_open_validate_partition, con = con)
  nis_open_check_year_values(sources, con)
  projections <- nis_open_project_sources(sources, con)
  union <- paste(projections, collapse = " UNION ALL BY NAME ")
  query <- dplyr::tbl(con, dbplyr::sql(paste0("SELECT * FROM (", union, ")")))
  source_names <- unlist(lapply(sources, function(source) source$schema$column_name),
    use.names = FALSE)
  query <- nis_open_normalize_names(query, source_names)
  nis_open_warn_2023(query)
  result <- nis_duckdb_attach_finalizer(query, connection$release, Filter(Negate(is.null),
    lapply(sources, function(source) source$owner)))
  on.exit(NULL, add = FALSE)
  result
}

nis_open_select <- function(path, years, error_call) {
  entries <- nis_open_entries(path, error_call)
  years <- nis_open_years(entries$found, years, error_call)
  nis_validate_layout_years(entries$entries, entries$found, years, error_call)
  list(path = entries$path, entries = entries$entries, found = entries$found, years = years)
}

nis_open_entries <- function(path, error_call) {
  if (!dir.exists(path)) {
    cli::cli_abort("`path` must name an existing directory.", call = error_call)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)

  entries <- list.files(path, pattern = "^NIS_[0-9]{4}[.]parquet$",
    full.names = TRUE, recursive = FALSE)
  hive_entries <- list.dirs(path, recursive = TRUE, full.names = TRUE)
  hive_entries <- hive_entries[grepl("^YEAR=[0-9]{4}$", basename(hive_entries))]
  entries <- unique(c(entries, hive_entries))
  found <- as.integer(sub("^(NIS_|YEAR=)([0-9]{4})([.]parquet)?$", "\\2",
    basename(entries)))
  entries <- entries[!is.na(found)]
  found <- found[!is.na(found)]
  if (length(found) == 0L) {
    cli::cli_abort("No `NIS_<year>.parquet` entries were found in `path`.", call = error_call)
  }
  list(path = path, entries = entries, found = found)
}

nis_open_years <- function(found, years, error_call) {
  if (is.null(years)) {
    years <- sort(found)
  }
  years <- nis_open_validate_years(years, error_call)
  missing <- setdiff(years, found)
  if (length(missing) > 0L) {
    cli::cli_abort(
      "No NIS Parquet entry was found for year{?s} {.val {missing}}.",
      call = error_call
    )
  }
  years
}

nis_open_validate_years <- function(years, error_call) {
  if (!is.numeric(years) || length(years) == 0L || anyNA(years)) {
    cli::cli_abort("`years` must be a non-empty vector of whole years.", call = error_call)
  }
  if (!nis_open_whole_years(years)) {
    cli::cli_abort("`years` must be a non-empty vector of whole years.", call = error_call)
  }
  years <- unique(as.integer(years))
  if (any(years < 2012L)) {
    cli::cli_abort("NIS years before 2012 are not supported.", call = error_call)
  }
  years
}

nis_open_whole_years <- function(years) {
  all(is.finite(years)) && all(years == as.integer(years))
}

nis_open_notice <- function(years) {
  if (any(years < 2016L)) {
    cli::cli_inform(c(
      "Experimental: years before 2016 store ICD-9-CM codes in {.field DX1}, {.field PR1}, ... slots.",
      i = "Flag them with {.code system = \"icd9\"}; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4) slots."
    ), .frequency = "once", .frequency_id = "easyNIS_icd9_layout")
  }
  invisible(NULL)
}

nis_open_sources <- function(selection, error_call) {
  year_entries <- selection$entries[selection$found %in% selection$years]
  sources <- unlist(lapply(year_entries, function(entry) {
    if (dir.exists(entry)) {
      list.files(entry, pattern = "[.]parquet$", recursive = TRUE,
        full.names = TRUE)
    } else {
      entry
    }
  }), use.names = FALSE)
  parent <- paste0(sub("/$", "", dirname(selection$path)), "/")
  relative <- substring(as.character(sources), nchar(parent) + 1L)
  partitions <- vapply(relative, nis_hive_partition_year, integer(1))
  selected <- is.na(partitions) | partitions %in% selection$years
  if (!any(selected)) {
    cli::cli_abort("The selected NIS entries contain no Parquet part files.",
      call = error_call)
  }
  paths <- normalizePath(sources[selected], winslash = "/", mustWork = TRUE)
  unique(data.frame(path = paths, partition_year = partitions[selected], row.names = NULL))
}

nis_hive_partition_year <- function(path) {
  components <- strsplit(dirname(path), "/", fixed = TRUE)[[1L]]
  partitions <- grep("^YEAR=[0-9]{4}$", components, value = TRUE)
  if (!length(partitions)) return(NA_integer_)
  as.integer(sub("^YEAR=", "", partitions[[length(partitions)]]))
}

nis_open_normalize_names <- function(query, source_names) {
  old_names <- colnames(query)
  new_names <- ifelse(grepl("[A-Z]", old_names), toupper(old_names), old_names)
  name_groups <- split(old_names, new_names)

  rename_groups <- name_groups[lengths(name_groups) == 1L]
  rename_map <- stats::setNames(rlang::syms(unlist(rename_groups)),
    names(rename_groups))
  query <- dplyr::rename(query, !!!rename_map)

  duplicate_groups <- name_groups[lengths(name_groups) > 1L]
  for (canonical in names(duplicate_groups)) {
    fields <- rlang::syms(duplicate_groups[[canonical]])
    merged <- Reduce(function(left, right) {
      rlang::expr(dplyr::coalesce(!!left, !!right))
    }, fields)
    query <- dplyr::mutate(query, !!canonical := !!merged) # dplyr name injection.
  }
  query <- dplyr::select(query, dplyr::all_of(names(name_groups)))

  nis_open_restore_spelling(query, source_names)
}

nis_open_restore_spelling <- function(query, source_names) {
  uppercase <- unique(source_names[grepl("[A-Z]", source_names)])
  keys <- nis_sql_identifier_key(uppercase)
  output <- colnames(query)
  output_keys <- nis_sql_identifier_key(output)
  source <- match(output_keys, keys)
  proposed <- output
  has_source <- !is.na(source)
  proposed[has_source] <- toupper(uppercase[source[has_source]])
  changed <- which(proposed != output)
  target <- nis_sql_identifier_key(proposed[changed])
  collides <- vapply(seq_along(changed), function(i) {
    target[[i]] %in% output_keys[-changed[[i]]]
  }, logical(1))
  duplicate <- duplicated(target) | duplicated(target, fromLast = TRUE)
  keep <- changed[!collides & !duplicate]
  if (!length(keep)) return(query)
  rename_map <- stats::setNames(rlang::syms(output[keep]), proposed[keep])
  dplyr::rename(query, !!!rename_map)
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
      .frequency = "once", .frequency_id = "easyNIS_totchg_2023"
    )
  }
  invisible(NULL)
}
