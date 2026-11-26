#' Add diagnosis code flags
#'
#' Each diagnosis slot is checked separately. Supplied prefixes are
#' case-insensitive, and periods and spaces in them are ignored. Slot values are
#' compared as stored, case sensitively, because NIS stores upper-case codes
#' without periods. Matching stays lazy in DuckDB and avoids per-row text
#' normalization. A flag definition can also be a list with `prefix`, `regex`,
#' and `exclude` character vectors. Prefixes and full-code regular expressions
#' are combined as alternatives; exclusions remove exact codes within each
#' slot, so a matching code in another slot can still set the flag. Regexes use
#' RE2-compatible syntax, are case-sensitive by default, and must match the
#' whole stored code. Character-vector definitions retain the original prefix
#' behavior.
#'
#' `system` picks which slots are tested. `"icd10"` reads `I10_DX1`, `I10_DX2`,
#' ...; `"icd9"` (experimental) reads `DX1`, `DX2`, ... as stored in NIS 2012
#' through Q3 2015. A prefix is only ever compared with slots of the chosen
#' system, so an ICD-10 flag never matches an ICD-9 slot and the reverse.
#' Slot suffixes must be positive integers without leading zeros. Malformed
#' slot names are ignored; an error is raised if no slots match the requested
#' position. The principal slot has suffix `1`; sparse and reordered slots
#' are supported.
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
#' @template dot-data
#' @param ... Named flag definitions, such as `heart_failure = "I50"`. For
#'   exclusions or full-code patterns, use a list such as
#'   `heart_failure = list(prefix = "I50", exclude = "I502")` or
#'   `heart_failure = list(regex = "I50(1|2)")`. Within a list, `prefix`,
#'   `regex`, and `exclude` can each be character vectors. Prefix and regex
#'   matches are combined; exclusions are exact and apply within each slot.
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
#'
#' # Exclude one exact subcode or match full codes with a regular expression
#' nis |>
#'   nis_flag_dx(hf_other = list(prefix = "I50", exclude = "I501")) |>
#'   dplyr::count(hf_other) |>
#'   dplyr::collect()
#' nis |>
#'   nis_flag_dx(hf_full = list(regex = "I50[0-9]{2}")) |>
#'   dplyr::count(hf_full) |>
#'   dplyr::collect()
nis_flag_dx <- function(.data, ..., position = c("any", "principal", "secondary"), system = c("icd10", "icd9")) {
  nis_flag_codes(.data, slots = "DX", ..., position = match.arg(position), system = match.arg(system))
}

#' Add procedure code flags
#'
#' Each procedure slot is checked separately, with the same prefix, regular
#' expression, exclusion, and `system` semantics as [nis_flag_dx()]. `"icd10"`
#' reads `I10_PR1`, ...; `"icd9"` (experimental) reads `PR1`, ...
#' Slot suffixes must be positive integers without leading zeros. Malformed
#' slot names are ignored; an error is raised if no slots match the requested
#' position. The principal slot has suffix `1`; sparse and reordered slots
#' are supported.
#'
#' @template dot-data
#' @param ... Named flag definitions, such as `ablation = "02L"`; see
#'   [nis_flag_dx()] for list definitions with exclusions or regexes.
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
nis_flag_pr <- function(.data, ..., position = c("any", "principal"), system = c("icd10", "icd9")) {
  nis_flag_codes(.data, slots = "PR", ..., position = match.arg(position), system = match.arg(system))
}

nis_flag_codes <- function(.data, slots, ..., position, system) {
  definitions <- rlang::enquos(..., .named = TRUE)
  if (length(definitions) == 0L || any(names(definitions) == "")) {
    cli::cli_abort("Supply one or more named code-prefix definitions.")
  }
  if (anyDuplicated(names(definitions))) {
    cli::cli_abort("Flag names must be unique.")
  }
  data_names <- nis_names(.data)
  if (!identical(names(definitions), nis_internal_names(.data, data_names, names(definitions)))) {
    cli::cli_abort("Flag names must not replace existing columns.")
  }

  rules <- lapply(definitions, normalize_flag_definition)
  regexes <- unique(unlist(lapply(rules, `[[`, "regex"), use.names = FALSE))
  if (length(regexes)) {
    validate_flag_regex(regexes)
  }

  slot_names <- nis_flag_slot_names(data_names, slots, system, position)
  flags <- lapply(rules, nis_code_match, data = .data, slot_names = slot_names)

  eligibility <- code_system_filter(.data, data_names, slots, system)
  flags <- lapply(flags, nis_in_code_system, eligibility = eligibility)
  dplyr::mutate(.data, !!!flags)
}

normalize_flag_definition <- function(definition) {
  value <- rlang::eval_tidy(definition)
  if (is.character(value)) {
    return(nis_prefix_rule(normalize_prefixes(value)))
  }
  validate_flag_definition_list(value)
  normalize_flag_definition_list(value)
}

validate_flag_definition_list <- function(value) {
  allowed <- c("prefix", "regex", "exclude")
  valid_names <- is.list(value) &&
    !is.null(names(value)) &&
    !anyDuplicated(names(value)) &&
    all(names(value) %in% allowed) &&
    length(value)
  if (!valid_names) {
    cli::cli_abort(paste(
      "Code flag definitions must be character vectors or named lists",
      "with `prefix`, `regex`, or `exclude`."
    ))
  }
  if (!any(names(value) %in% c("prefix", "regex"))) {
    cli::cli_abort("A code flag definition must include `prefix` or `regex`.")
  }
  invisible(value)
}

normalize_flag_definition_list <- function(value) {
  prefix <- normalize_flag_prefixes(value$prefix)
  regex <- normalize_flag_regexes(value$regex)
  exclude <- normalize_flag_exclusions(value$exclude)
  if (!length(prefix) && !length(regex)) {
    cli::cli_abort("A code flag definition must include a non-empty `prefix` or `regex`.")
  }
  list(prefix = prefix, regex = regex, exclude = exclude)
}

normalize_flag_prefixes <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  normalize_prefixes(value)
}

normalize_flag_regexes <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  if (!is.character(value) || anyNA(value)) {
    cli::cli_abort("`regex` must be a non-missing character vector.")
  }
  unique(value)
}

normalize_flag_exclusions <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  if (!is.character(value) || anyNA(value)) {
    cli::cli_abort("`exclude` must be a non-missing character vector.")
  }
  unique(value)
}

validate_flag_regex <- function(patterns) {
  con <- nis_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (pattern in patterns) {
    tryCatch(
      DBI::dbGetQuery(con, "SELECT regexp_full_match('', ?) AS valid", params = list(pattern)),
      error = function(error) {
        cli::cli_abort("Invalid or unsupported DuckDB regular expression {.val {pattern}}.")
      }
    )
  }
  invisible(patterns)
}

nis_sql_regex_match <- function(patterns, column) {
  per_pattern <- lapply(patterns, function(pattern) {
    rlang::expr(regexp_full_match(as.character(!!rlang::sym(column)), !!pattern))
  })
  rlang::expr(dplyr::coalesce(!!reduce_or(per_pattern), FALSE))
}

normalize_prefixes <- function(value, arg = NULL) {
  if (!is.character(value) || length(value) == 0L || anyNA(value)) {
    if (is.null(arg)) {
      cli::cli_abort("Code prefixes must be non-missing character vectors.")
    }
    cli::cli_abort("{arg} must be non-missing character prefixes.")
  }
  value <- toupper(gsub("[.[:space:]]", "", value))
  if (!all(grepl("^[A-Z0-9]+$", value))) {
    cli::cli_abort("Code prefixes may contain only letters and numbers.")
  }
  unique(value)
}

# Data-frame prefix checks use `startsWith()`, which compares bytes and never
# errors on malformed text. Regex definitions use DuckDB's RE2 engine for the
# same whole-code matching semantics as lazy queries.
nis_code_match <- function(rule, data, slot_names) {
  local <- is.data.frame(data)
  per_slot <- lapply(slot_names, function(column) {
    value <- rlang::expr(as.character(!!rlang::sym(column)))
    included <- list()
    if (length(rule$prefix)) {
      prefix <- if (local) {
        reduce_or(lapply(rule$prefix, function(code) rlang::expr(startsWith(!!value, !!code))))
      } else {
        nis_sql_match(rule$prefix, column)
      }
      included <- list(prefix)
    }
    if (length(rule$regex)) {
      regex <- if (local) {
        rlang::expr(nis_frame_regex_match(!!value, !!rule$regex))
      } else {
        nis_sql_regex_match(rule$regex, column)
      }
      included <- c(included, list(regex))
    }
    matched <- reduce_or(included)
    if (!length(rule$exclude)) {
      return(matched)
    }
    excluded <- rlang::expr(!!value %in% !!rule$exclude)
    nis_and_expr(matched, rlang::expr(!dplyr::coalesce(!!excluded, FALSE)))
  })
  rlang::expr(dplyr::coalesce(!!reduce_or(per_slot), FALSE))
}

nis_prefix_rule <- function(prefix) {
  list(prefix = prefix, regex = character(), exclude = character())
}

nis_frame_regex_match <- function(values, patterns) {
  if (length(values) == 0L) {
    return(logical())
  }
  con <- nis_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(
    con,
    "regex_values",
    data.frame(
      row_id = seq_along(values),
      code = values,
      stringsAsFactors = FALSE
    ),
    temporary = TRUE
  )

  code <- as.character(DBI::dbQuoteIdentifier(con, "code"))
  row_id <- as.character(DBI::dbQuoteIdentifier(con, "row_id"))
  matches <- paste0("COALESCE(regexp_full_match(", code, ", ?), FALSE)")
  match_expression <- paste(rep(matches, length(patterns)), collapse = " OR ")
  sql <- paste0("SELECT ", row_id, ", (", match_expression, ") AS matched FROM regex_values ORDER BY ", row_id)
  result <- DBI::dbGetQuery(con, sql, params = as.list(patterns))
  result$matched
}

nis_sql_match <- function(prefix, column) {
  per_prefix <- lapply(prefix, function(code) {
    # jarl-ignore string_boundary: Keep the existing SQL SUBSTR translation.
    rlang::expr(substr(!!rlang::sym(column), 1L, !!nchar(code)) == !!code)
  })
  rlang::expr(dplyr::coalesce(!!reduce_or(per_prefix), FALSE))
}
