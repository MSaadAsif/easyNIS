#' Open annual NIS Parquet files lazily
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open. Defaults to every matching year.
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
  if (any(years < 2016L)) {
    cli::cli_abort("ICD-9 years are not yet supported; use 2016 or later.")
  }
  missing <- setdiff(years, found)
  if (length(missing) > 0L) {
    cli::cli_abort("No NIS Parquet entry was found for year{?s} {.val {missing}}.")
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
        "i" = "HCUP adjusts it for states missing from 2023, so charges and costs built from it differ in definition from earlier years.",
        "i" = "{.fn nis_open} leaves {.field TOTCHG} unchanged; opt in with {.code charges = \"TOTCHG_2023\"}.",
        "i" = "The 2023 layout support is experimental and unverified against real 2023 data."),
      .frequency = "once", .frequency_id = "easyNIS_totchg_2023"
    )
  }
  dplyr::select(query, dplyr::all_of(output_names))
}

#' Add ICD-10 diagnosis prefix flags
#'
#' Each diagnosis slot is checked separately. Supplied prefixes are
#' case-insensitive, and periods and spaces in them are ignored. Slot values are
#' compared as stored, byte for byte, because NIS stores upper-case codes
#' without periods; malformed UTF-8 therefore cannot raise an error. Matching
#' stays lazy on Arrow queries and avoids per-row text normalization.
#'
#' @param .data A data frame or lazy Arrow query.
#' @param ... Named flag definitions, such as `heart_failure = "I50"`.
#' @param position Slots to check: all slots, the principal slot, or secondary
#'   slots only.
#'
#' @return `.data` with one logical column per named definition.
#' @export
nis_flag_dx <- function(.data, ..., position = c("any", "principal", "secondary")) {
  nis_flag_codes(.data, slots = "DX", ..., position = match.arg(position))
}

#' Add ICD-10 procedure prefix flags
#'
#' Each procedure slot is checked separately. Supplied prefixes are
#' case-insensitive, and periods and spaces in them are ignored. Slot values are
#' compared as stored, byte for byte, because NIS stores upper-case codes
#' without periods; malformed UTF-8 therefore cannot raise an error. Matching
#' stays lazy on Arrow queries and avoids per-row text normalization.
#'
#' @param .data A data frame or lazy Arrow query.
#' @param ... Named flag definitions, such as `ablation = "02L"`.
#' @param position Slots to check: all slots or the principal slot only.
#'
#' @return `.data` with one logical column per named definition.
#' @export
nis_flag_pr <- function(.data, ..., position = c("any", "principal")) {
  nis_flag_codes(.data, slots = "PR", ..., position = match.arg(position))
}

nis_flag_codes <- function(.data, slots, ..., position) {
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

  slot_names <- grep(paste0("^I10_", slots, "[0-9]+$"), names(.data), value = TRUE)
  slot_number <- as.integer(sub(paste0("^I10_", slots), "", slot_names))
  if (position == "principal") {
    slot_names <- slot_names[slot_number == 1L]
  } else if (position == "secondary") {
    slot_names <- slot_names[slot_number > 1L]
  }
  if (length(slot_names) == 0L) {
    cli::cli_abort("No ICD-10 {slots} columns match the requested position.")
  }

  flags <- if (is.data.frame(.data)) {
    lapply(prefixes, frame_match, slot_names = slot_names)
  } else {
    projection <- dplyr::select(.data, dplyr::everything())$selected_columns
    lapply(prefixes, arrow_match, slots = projection[slot_names])
  }

  dplyr::mutate(.data, !!!flags)
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
