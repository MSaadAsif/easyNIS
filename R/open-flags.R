#' Open annual NIS Parquet files lazily
#'
#' @param path Directory containing `NIS_<year>.parquet` files or directories.
#' @param years Optional years to open. Defaults to every matching year.
#'
#' @return A lazy Arrow query with case-normalized columns.
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
  dplyr::select(query, dplyr::all_of(names(name_groups)))
}

#' Add ICD-10 diagnosis prefix flags
#'
#' Each diagnosis slot is checked separately. Prefixes are case-insensitive;
#' periods and spaces are removed from both the supplied prefixes and codes.
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
#' Each procedure slot is checked separately. Prefixes are case-insensitive;
#' periods and spaces are removed from both the supplied prefixes and codes.
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

  flags <- lapply(seq_along(definitions), function(i) {
    per_slot <- lapply(slot_names, function(column) {
      field <- rlang::sym(column)
      normalized <- rlang::expr(stringr::str_to_upper(
        stringr::str_remove_all(as.character(!!field), "[.[:space:]]")
      ))
      per_prefix <- lapply(prefixes[[i]], function(prefix) {
        rlang::expr(stringr::str_starts(!!normalized, !!prefix))
      })
      matches <- Reduce(function(left, right) {
        rlang::expr((!!left) | (!!right))
      }, per_prefix)
      rlang::expr(dplyr::coalesce(!is.na(!!field) & (!!matches), FALSE))
    })
    matches <- Reduce(function(left, right) {
      rlang::expr((!!left) | (!!right))
    }, per_slot)
    rlang::set_names(list(matches), names(definitions)[[i]])
  })

  dplyr::mutate(.data, !!!unlist(flags, recursive = FALSE))
}
