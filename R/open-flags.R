#' Open annual NIS Parquet files lazily
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open, 2012 or later. Defaults to every
#'   matching year. Years before 2016 are experimental: they hold ICD-9-CM
#'   codes in `DX*`/`PR*` slots, and 2015 holds both systems (see
#'   [nis_flag_dx()]).
#'
#' @return A lazy Arrow query with case-normalized columns. Experimental 2023
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
  if (!dir.exists(path)) {
    cli::cli_abort("`path` must name an existing directory.")
  }

  entries <- list.files(path, pattern = "^NIS_[0-9]{4}[.]parquet$",
    full.names = TRUE, recursive = FALSE)
  found <- as.integer(sub("^NIS_([0-9]{4})[.]parquet$", "\\1",
    basename(entries)))
  if (length(found) == 0L) {
    cli::cli_abort("No `NIS_<year>.parquet` entries were found in `path`.")
  }

  if (is.null(years)) {
    years <- sort(found)
  }
  if (!is.numeric(years) || length(years) == 0L || anyNA(years) ||
      any(!is.finite(years)) || any(years != as.integer(years))) {
    cli::cli_abort("`years` must be a non-empty vector of whole years.")
  }
  years <- unique(as.integer(years))
  if (any(years < 2012L)) {
    cli::cli_abort("NIS years before 2012 are not supported.")
  }
  missing <- setdiff(years, found)
  if (length(missing) > 0L) {
    cli::cli_abort("No NIS Parquet entry was found for year{?s} {.val {missing}}.")
  }
  if (any(years < 2016L)) {
    cli::cli_inform(c(
      "Experimental: years before 2016 store ICD-9-CM codes in {.field DX1}, {.field PR1}, ... slots.",
      i = "Flag them with {.code system = \"icd9\"}; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4) slots."
    ))
  }

  year_entries <- entries[match(years, found)]
  sources <- unlist(lapply(year_entries, function(entry) {
    if (dir.exists(entry)) {
      list.files(entry, pattern = "[.]parquet$", recursive = TRUE,
        full.names = TRUE)
    } else {
      entry
    }
  }), use.names = FALSE)
  if (length(sources) == 0L) {
    cli::cli_abort("The selected NIS entries contain no Parquet part files.")
  }
  query <- arrow::open_dataset(sources, format = "parquet", unify_schemas = TRUE)
  old_names <- names(query)
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
    query <- dplyr::mutate(query, !!canonical := !!merged)
  }
  output_names <- names(name_groups)
  if ("TOTCHG_2023" %in% output_names) {
    cli::cli_warn(
      c("This query contains {.field TOTCHG_2023}, which is not comparable to {.field TOTCHG}.",
        "i" = paste(
          "HCUP adjusts it for states missing from 2023, so charges and costs",
          "built from it differ in definition from earlier years."
        ),
        "i" = "{.fn nis_open} leaves {.field TOTCHG} unchanged; opt in with {.code charges = \"TOTCHG_2023\"}.",
        "i" = "The 2023 layout support is experimental and unverified against real 2023 data."),
      .frequency = "once", .frequency_id = "easyNIS_totchg_2023"
    )
  }
  dplyr::select(query, dplyr::all_of(output_names))
}

#' Add diagnosis prefix flags
#'
#' Each diagnosis slot is checked separately. Supplied prefixes are
#' case-insensitive, and periods and spaces in them are ignored. Slot values are
#' compared as stored, byte for byte, because NIS stores upper-case codes
#' without periods; malformed UTF-8 therefore cannot raise an error. Matching
#' stays lazy on Arrow queries and avoids per-row text normalization.
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
#' @param .data A data frame or lazy Arrow query.
#' @param ... Named flag definitions, such as `heart_failure = "I50"`.
#' @param position Slots to check: all slots, the principal slot, or secondary
#'   slots only.
#' @param system Code system of the slots to check: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#'
#' @return `.data` with one logical column per named definition.
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
#' @param .data A data frame or lazy Arrow query.
#' @param ... Named flag definitions, such as `ablation = "02L"`.
#' @param position Slots to check: all slots or the principal slot only.
#' @param system Code system of the slots to check: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#'
#' @return `.data` with one logical column per named definition.
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
  if (any(names(definitions) %in% names(.data))) {
    cli::cli_abort("Flag names must not replace existing columns.")
  }

  prefixes <- lapply(definitions, function(definition) {
    value <- rlang::eval_tidy(definition)
    if (!is.character(value) || length(value) == 0L || anyNA(value)) {
      cli::cli_abort("Code prefixes must be non-missing character vectors.")
    }
    value <- toupper(gsub("[.[:space:]]", "", value))
    if (any(!grepl("^[A-Z0-9]+$", value))) {
      cli::cli_abort("Code prefixes may contain only letters and numbers.")
    }
    unique(value)
  })

  stem <- paste0(if (system == "icd10") "I10_", slots)
  slot_names <- grep(paste0("^", stem, "[0-9]+$"), names(.data), value = TRUE)
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
    projection <- dplyr::select(.data, dplyr::everything())$selected_columns
    lapply(prefixes, arrow_match, slots = projection[slot_names])
  }

  eligibility <- code_system_filter(names(.data), slots, system)
  if (!is.null(eligibility)) {
    flags <- lapply(flags, function(flag) {
      rlang::expr((!!eligibility) & (!!flag))
    })
  }
  dplyr::mutate(.data, !!!flags)
}

code_system_filter <- function(columns, slots, system) {
  conditions <- list()
  version_name <- paste0(slots, "VER")
  version <- if (system == "icd9") 9L else 10L
  if (version_name %in% columns) {
    field <- rlang::sym(version_name)
    conditions <- c(conditions, list(rlang::expr(is.na(!!field) | !!field == !!version)))
  }
  if ("YEAR" %in% columns) {
    year_range <- if (system == "icd9") {
      rlang::expr(YEAR >= 2012L & YEAR <= 2015L)
    } else {
      rlang::expr(YEAR >= 2015L)
    }
    conditions <- c(conditions, list(rlang::expr(is.na(YEAR) | !!year_range)))
    if ("DQTR" %in% columns) {
      quarters <- if (system == "icd9") 1:3 else 4L
      quarter <- rlang::sym("DQTR")
      conditions <- c(conditions, list(rlang::expr(
        is.na(YEAR) | YEAR != 2015L | is.na(!!quarter) | !!quarter %in% !!quarters
      )))
    }
  }
  if (length(conditions) == 0L) return(NULL)
  Reduce(function(left, right) rlang::expr((!!left) & (!!right)), conditions)
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

# Arrow queries get native compute expressions built on the query's current
# projection, so columns created or changed by an earlier `mutate()` are
# respected. One prefix is a plain `starts_with` per slot. Several prefixes cut
# each slot to the prefix length as bytes and test set membership, so cost
# grows with the number of distinct prefix lengths instead of the number of
# prefixes. Neither validates UTF-8.
arrow_match <- function(prefix, slots) {
  kernel <- arrow::Expression$create
  or_all <- function(terms) {
    Reduce(function(left, right) kernel("or_kleene", left, right), terms)
  }
  by_length <- split(prefix, nchar(prefix))
  value_sets <- lapply(by_length, function(codes) {
    arrow::Array$create(lapply(codes, charToRaw), type = arrow::binary())
  })

  per_slot <- lapply(slots, function(slot) {
    if (length(prefix) == 1L) {
      return(kernel("starts_with", slot, options = list(pattern = prefix)))
    }
    as_bytes <- kernel("cast", slot, options = list(to_type = arrow::binary()))
    or_all(lapply(seq_along(by_length), function(i) {
      kernel("is_in",
        kernel("binary_slice", as_bytes,
          options = list(start = 0L, stop = nchar(by_length[[i]][[1L]]))),
        options = list(value_set = value_sets[[i]], skip_nulls = FALSE))
    }))
  })
  kernel("coalesce", or_all(per_slot), arrow::Expression$scalar(FALSE))
}

reduce_or <- function(terms) {
  Reduce(function(left, right) rlang::expr((!!left) | (!!right)), terms)
}
