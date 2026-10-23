nis_validate_layout_years <- function(entries, found, years, error_call) {
  annual <- !dir.exists(entries)
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
#'
#' @details `nis_open()` reads Parquet directly with DuckDB and returns a
#'   DuckDB-backed dbplyr table. It accepts annual `NIS_<year>.parquet` files
#'   and Hive directories named `YEAR=YYYY` containing Parquet parts. If a part file
#'   has a physical `YEAR` column, its non-missing values must agree with the
#'   directory year; missing or absent physical values use the partition year.
#'   Schemas are combined by column name, including when annual files and Hive
#'   partitions are mixed. When annual types differ, DuckDB may promote them;
#'   for example, an integer field combined with a character field is returned
#'   as character. When present, `YEAR` is validated and returned as integer;
#'   invalid values identify the offending file in an error. The connection
#'   remains open while the lazy table is in use and closes after it is released.
#'   Use `dplyr::collect()` to return
#'   data to R. Years before 2016 emit an experimental ICD-9 layout notice once
#'   per R session. The `engine` argument was removed entirely; omit it regardless
#'   of the value used in older code.
#'   String columns with malformed UTF-8 may fail during a native Parquet scan;
#'   validate or repair those values before writing Parquet files.
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
nis_open <- function(path, years = NULL) {
  error_call <- rlang::current_call()
  selected <- nis_open_select(path, years, error_call)
  nis_open_notice(selected$years)
  sources <- nis_open_sources(selected$entries, selected$found, selected$years,
    error_call)
  con <- nis_duckdb_connect() # nolint: object_usage_linter
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE),
    add = TRUE)
  nis_validate_hive_years(con, sources) # nolint: object_usage_linter
  nis_validate_year_values(con, sources) # nolint: object_usage_linter
  query <- nis_duckdb_query_from_parquet(con, sources) # nolint: object_usage_linter
  query <- nis_open_normalize_names(query)
  query <- nis_open_warn_2023(query)
  on.exit(NULL, add = FALSE)
  nis_duckdb_attach_finalizer(query, con) # nolint: object_usage_linter
}

nis_open_select <- function(path, years, error_call) {
  entries <- nis_open_entries(path, error_call)
  years <- nis_open_years(entries$found, years, error_call)
  nis_validate_layout_years(entries$entries, entries$found, years, error_call)
  list(entries = entries$entries, found = entries$found, years = years)
}

nis_open_entries <- function(path, error_call) {
  if (!dir.exists(path)) {
    cli::cli_abort("`path` must name an existing directory.", call = error_call)
  }

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
  list(entries = entries, found = found)
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

nis_open_sources <- function(entries, found, years, error_call) {
  year_entries <- entries[found %in% years]
  sources <- unlist(lapply(year_entries, function(entry) {
    if (dir.exists(entry)) {
      list.files(entry, pattern = "[.]parquet$", recursive = TRUE,
        full.names = TRUE)
    } else {
      entry
    }
  }), use.names = FALSE)
  if (length(sources) == 0L) {
    cli::cli_abort("The selected NIS entries contain no Parquet part files.",
      call = error_call)
  }
  unique(sources)
}

nis_open_normalize_names <- function(query) {
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
  dplyr::select(query, dplyr::all_of(names(name_groups)))
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
  query
}

#' Add diagnosis prefix flags
#'
#' Each diagnosis slot is checked separately. Supplied prefixes are
#' case-insensitive, and periods and spaces in them are ignored. Slot values are
#' compared as stored, case sensitively, because NIS stores upper-case codes
#' without periods. Matching stays lazy in DuckDB and avoids per-row text
#' normalization.
#'
#' `system` picks which slots are tested. `"icd10"` reads `I10_DX1`, `I10_DX2`,
#' ...; `"icd9"` (experimental) reads `DX1`, `DX2`, ... as stored in NIS 2012
#' through Q3 2015. A prefix is only ever compared with slots of the chosen
#' system, so an ICD-10 flag never matches an ICD-9 slot and the reverse.
#'
#' In 2015 the Q1-Q3 discharges carry ICD-9 codes and the Q4 discharges carry
#' ICD-10 codes. HCUP is understood to recommend `DXVER` (9 or 10) to
#' distinguish them, because `DQTR` can be missing (UNVERIFIED: secondhand); `PRVER` describes the procedure system.
#' Non-missing version indicators must agree with `system`; non-missing
#' `YEAR` and, in 2015, `DQTR` must also agree. Conflicting or invalid
#' indicators yield `FALSE`. Missing indicators rely on the slot namespace:
#' callers must preserve the official names and leave inapplicable slots
#' missing. Shared slots containing both systems are not supported.
#' `FALSE` means "not flagged under that code system", not "condition absent".
#' A study that crosses October 2015 needs
#' analyst-supplied code sets for both systems, flagged in two calls and
#' combined, for example
#' `nis_flag_dx(hf10 = "I50") |> nis_flag_dx(hf9 = "428", system = "icd9") |>
#' dplyr::mutate(hf = hf10 | hf9)`. easyNIS ships no code lists and no ICD-9 to
#' ICD-10 crosswalk, and even with both code sets, counts of a condition can
#' break at the transition.
#'
#' @param .data A data frame or lazy DuckDB query.
#' @param ... Named flag definitions, such as `heart_failure = "I50"`.
#' @param position Slots to check: all slots, the principal slot, or secondary
#'   slots only.
#' @param system Code system of the slots to check: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#'
#' @return `.data` with one logical column per named definition.
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020))
#' nis |>
#'   nis_flag_dx(heart_failure = "I50") |>
#'   dplyr::count(heart_failure) |>
#'   dplyr::collect()
#'
#' # Several prefixes, restricted to the principal diagnosis
#' nis |>
#'   nis_flag_dx(hf_or_diabetes = c("I50", "E11"), position = "principal") |>
#'   dplyr::count(hf_or_diabetes) |>
#'   dplyr::collect()
nis_flag_dx <- function(.data, ..., position = c("any", "principal", "secondary"),
                        system = c("icd10", "icd9")) {
  nis_flag_codes(.data, slots = "DX", ..., position = match.arg(position),
    system = match.arg(system))
}

#' Add procedure prefix flags
#'
#' Each procedure slot is checked separately, with the same prefix rules, byte
#' for byte comparison, and `system` semantics as [nis_flag_dx()]. `"icd10"`
#' reads `I10_PR1`, ...; `"icd9"` (experimental) reads `PR1`, ... Prefixes only
#' match slots of the chosen system, so a flag over a mixed 2015 query is
#' `FALSE` on discharges coded in the other system.
#'
#' @param .data A data frame or lazy DuckDB query.
#' @param ... Named flag definitions, such as `ablation = "02L"`.
#' @param position Slots to check: all slots or the principal slot only.
#' @param system Code system of the slots to check: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#'
#' @return `.data` with one logical column per named definition.
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020))
#' nis |>
#'   nis_flag_pr(ablation = "02L") |>
#'   dplyr::count(ablation) |>
#'   dplyr::collect()
nis_flag_pr <- function(.data, ..., position = c("any", "principal"),
                        system = c("icd10", "icd9")) {
  nis_flag_codes(.data, slots = "PR", ..., position = match.arg(position),
    system = match.arg(system))
}

nis_flag_codes <- function(.data, slots, ..., position, system) {
  definitions <- rlang::enquos(..., .named = TRUE)
  if (length(definitions) == 0L || any(names(definitions) == "")) {
    cli::cli_abort("Supply one or more named code-prefix definitions.")
  }
  if (anyDuplicated(names(definitions))) {
    cli::cli_abort("Flag names must be unique.")
  }
  data_names <- nis_names(.data) # nolint: object_usage_linter
  if (any(names(definitions) %in% data_names)) {
    cli::cli_abort("Flag names must not replace existing columns.")
  }

  prefixes <- lapply(definitions, function(definition) {
    normalize_prefixes(rlang::eval_tidy(definition))
  })

  stem <- paste0(if (system == "icd10") "I10_", slots)
  slot_names <- grep(paste0("^", stem, "[0-9]+$"), data_names, value = TRUE)
  slot_number <- as.integer(sub(paste0("^", stem), "", slot_names))
  if (position == "principal") {
    slot_names <- slot_names[slot_number == 1L]
  } else if (position == "secondary") {
    slot_names <- slot_names[slot_number > 1L]
  }
  if (length(slot_names) == 0L) {
    cli::cli_abort(paste(
      "No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} {slots} columns",
      "({stem}<n>) match the requested position."
    ))
  }

  flags <- if (is.data.frame(.data)) {
    lapply(prefixes, frame_match, slot_names = slot_names)
  } else {
    lapply(prefixes, function(prefix) {
      reduce_or(lapply(slot_names, function(column) {
        nis_sql_match(prefix, column) # nolint: object_usage_linter
      }))
    })
  }

  eligibility <- code_system_filter(.data, data_names, slots, system)
  if (!is.null(eligibility)) {
    flags <- lapply(flags, function(flag) {
      nis_and_expr(eligibility, flag) # nolint: object_usage_linter
    })
  }
  dplyr::mutate(.data, !!!flags)
}

normalize_prefixes <- function(value, arg = NULL) {
  if (!is.character(value) || length(value) == 0L || anyNA(value)) {
    if (is.null(arg)) {
      cli::cli_abort("Code prefixes must be non-missing character vectors.")
    }
    cli::cli_abort("{arg} must be non-missing character prefixes.")
  }
  value <- toupper(gsub("[.[:space:]]", "", value))
  if (any(!grepl("^[A-Z0-9]+$", value))) {
    cli::cli_abort("Code prefixes may contain only letters and numbers.")
  }
  unique(value)
}

code_system_filter <- function(data, columns, slots, system) {
  conditions <- list()
  version_name <- paste0(slots, "VER")
  version <- if (system == "icd9") 9L else 10L
  if (version_name %in% columns) {
    field <- rlang::sym(version_name)
    missing_version <- nis_is_missing_expr(data, version_name) # nolint: object_usage_linter
    conditions <- c(conditions, list(rlang::expr(
      !!missing_version | !!field == !!version
    )))
  }
  if ("YEAR" %in% columns) {
    missing_year <- nis_is_missing_expr(data, "YEAR") # nolint: object_usage_linter
    # rlang expressions use data-masked names.
    year_range <- if (system == "icd9") {
      rlang::expr(YEAR >= 2012L & YEAR <= 2015L)
    } else {
      rlang::expr(YEAR >= 2015L)
    }
    conditions <- c(conditions, list(rlang::expr(!!missing_year | !!year_range)))
    if ("DQTR" %in% columns) {
      quarters <- if (system == "icd9") 1:3 else 4L
      quarter <- rlang::sym("DQTR")
      missing_quarter <- nis_is_missing_expr(data, "DQTR") # nolint: object_usage_linter
      conditions <- c(conditions, list(rlang::expr(
        !!missing_year | YEAR != 2015L | !!missing_quarter |
          !!quarter %in% !!quarters
      )))
    }
  }
  if (length(conditions) == 0L) return(NULL)
  Reduce(nis_and_expr, conditions) # nolint: object_usage_linter
}

# Data frames use `startsWith()`, which compares bytes and never errors on
# malformed text; a missing slot value counts as no match.
frame_match <- function(prefix, slot_names) {
  per_slot <- lapply(slot_names, function(column) {
    per_prefix <- lapply(prefix, function(code) {
      rlang::expr(startsWith(as.character(!!rlang::sym(column)), !!code))
    })
    reduce_or(per_prefix)
  })
  rlang::expr(dplyr::coalesce(!!reduce_or(per_slot), FALSE))
}

reduce_or <- function(terms) {
  Reduce(function(left, right) rlang::expr((!!left) | (!!right)), terms)
}
