#' Flag procedure timing relative to an index procedure
#'
#' Compares procedure slots with the correspondingly numbered PRDAY values.
#' The earliest valid index day is used when the index procedure occurs in
#' multiple slots. A slot matching both prefix sets counts as both procedures.
#' Prefixes follow the normalization and matching rules of [nis_flag_pr()].
#' Factor and ordered-factor PRDAY columns are interpreted by their labels,
#' not their internal level numbers. Values that decode to missing numeric days
#' are handled as missing. Input columns are preserved.
#' Negative days (including HCUP sentinel values), non-finite values, and
#' missing days are unknown.
#' If either procedure is absent, the result is FALSE. Otherwise, any outcome
#' with a known day satisfying the relation returns TRUE. If none does and a
#' matching procedure has an unknown day, exclude returns FALSE,
#' assume_same_day treats that day as 0, and indeterminate returns NA.
#'
#' on_or_after tests outcome day >= earliest index day; after tests >; before
#' tests <; same_day tests equality. within_days tests whether the outcome is
#' from 0 through window days after the earliest index day, inclusive.
#'
#' @template dot-data
#' @param index_pr Character vector of index procedure code prefixes.
#' @param outcome_pr Character vector of outcome procedure code prefixes.
#' @param name Single name for the new logical flag.
#' @param relation Timing relation: on_or_after, after, before, same_day, or
#'   within_days.
#' @param window Required non-negative integer for within_days; otherwise NULL.
#' @param missing_day How to handle unknown days: exclude returns FALSE,
#'   assume_same_day uses day 0, and indeterminate returns NA unless a
#'   determinate match is TRUE.
#' @param system Code system: icd10 uses I10_PR followed by a slot number;
#'   icd9 uses PR followed by a slot number.
#'
#' @return .data with the logical column named by name.
#' @family cohort-definition
#' @seealso [Defining cohorts](../articles/cohorts.html).
#' @export
#' @examples
#' toy <- data.frame(I10_PR1 = c("02UG0JZ", "0JH604Z"), PRDAY1 = c(0L, 1L))
#' nis_flag_pr_timing(toy, "02UG0", "0JH60")
nis_flag_pr_timing <- function(
  .data,
  index_pr,
  outcome_pr,
  name = "outcome_post_index",
  relation = c("on_or_after", "after", "before", "same_day", "within_days"),
  window = NULL,
  missing_day = c("exclude", "assume_same_day", "indeterminate"),
  system = c("icd10", "icd9")
) {
  error_call <- rlang::current_call()
  relation <- match.arg(relation)
  missing_day <- match.arg(missing_day)
  system <- match.arg(system)
  data_names <- nis_names(.data)
  name <- timing_validate_name(name, .data, data_names, error_call)
  timing_validate_window(relation, window, error_call)
  if (relation == "within_days") {
    window <- as.integer(window)
  }
  index_pr <- normalize_prefixes(index_pr, "index_pr")
  outcome_pr <- normalize_prefixes(outcome_pr, "outcome_pr")
  layout <- nis_procedure_slots(data_names, system, error_call)
  if (!layout$has_days) {
    cli::cli_abort("No PRDAY<n> columns were found for procedure timing.", call = error_call)
  }

  reserved <- c(data_names, name)
  matched <- timing_matches(.data, layout$procedure, index_pr, outcome_pr, reserved)
  .data <- matched$data
  decoded <- lapply(layout$day, nis_procedure_day, data = .data)
  days <- lapply(decoded, function(day) {
    if (missing_day == "assume_same_day") rlang::expr(dplyr::coalesce(!!day$usable, 0)) else day$usable
  })
  index_matches <- matched$index_matches
  outcome_matches <- matched$outcome_matches
  index <- timing_index_days(.data, days, index_matches, reserved, matched$temporary_names)
  .data <- index$data
  temporary_names <- index$temporary_names
  result <- timing_result(days, decoded, index_matches, outcome_matches, index$index_day, relation, window, missing_day)
  eligibility <- code_system_filter(.data, data_names, "PR", system)
  result <- nis_in_code_system(result, eligibility)
  .data <- dplyr::mutate(.data, !!name := !!result)
  dplyr::select(.data, -dplyr::all_of(temporary_names))
}

timing_validate_name <- function(name, data, data_names, error_call) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    cli::cli_abort("name must be a single non-empty column name.", call = error_call)
  }
  name <- as.character(name)
  if (!identical(name, nis_internal_names(data, data_names, name))) {
    cli::cli_abort("name must not replace an existing column.", call = error_call)
  }
  name
}

timing_validate_window <- function(relation, window, error_call) {
  if (relation == "within_days") {
    if (!timing_window_scalar(window) || !timing_window_range(window) || window != as.integer(window)) {
      cli::cli_abort("window must be a single non-negative integer for within_days.", call = error_call)
    }
  } else if (!is.null(window)) {
    cli::cli_abort("window must be NULL unless relation is within_days.", call = error_call)
  }
}

timing_window_scalar <- function(window) {
  is.numeric(window) && length(window) == 1L && !is.na(window) && is.finite(window)
}

timing_window_range <- function(window) {
  window >= 0 && window <= .Machine$integer.max
}

timing_matches <- function(data, procedure_names, index_pr, outcome_pr, data_names) {
  index <- lapply(procedure_names, function(column) {
    nis_code_match(nis_prefix_rule(index_pr), data, column)
  })
  outcome <- lapply(procedure_names, function(column) {
    nis_code_match(nis_prefix_rule(outcome_pr), data, column)
  })
  count <- length(index) + length(outcome)
  names <- nis_internal_names(data, data_names, paste0(".easyNIS_pr_timing_match_", seq_len(count)))
  data <- dplyr::mutate(data, !!!stats::setNames(c(index, outcome), names))
  list(
    data = data,
    temporary_names = names,
    index_matches = rlang::syms(names[seq_along(index)]),
    outcome_matches = rlang::syms(names[length(index) + seq_along(outcome)])
  )
}

timing_index_days <- function(data, days, index_matches, data_names, temporary_names) {
  index_days <- Map(
    function(day, matched) {
      rlang::expr(dplyr::if_else(!!matched, !!day, NA_real_))
    },
    days,
    index_matches
  )
  index_candidates <- paste0(".easyNIS_pr_timing_index_day_", seq_along(index_days))
  index_names <- nis_internal_names(data, c(data_names, temporary_names), index_candidates)
  data <- dplyr::mutate(data, !!!stats::setNames(index_days, index_names))
  index_symbols <- rlang::syms(index_names)
  valid <- timing_or_expr(lapply(index_symbols, function(day) rlang::expr(!is.na(!!day))))
  min_day <- rlang::expr(pmin(!!!index_symbols, na.rm = TRUE))
  min_name <- nis_internal_names(data, c(data_names, temporary_names, index_names), ".easyNIS_pr_timing_min_index_day")
  data <- dplyr::mutate(data, !!min_name := dplyr::if_else(!!valid, !!min_day, NA_real_))
  list(data = data, index_day = rlang::sym(min_name), temporary_names = c(temporary_names, index_names, min_name))
}

timing_result <- function(days, decoded, index_matches, outcome_matches, index_day, relation, window, missing_day) {
  index_present <- timing_or_expr(index_matches)
  outcome_present <- timing_or_expr(outcome_matches)
  checks <- Map(
    function(day, matched) {
      timing_relation_check(day, matched, index_day, relation, window)
    },
    days,
    outcome_matches
  )
  success <- timing_or_expr(checks)
  if (missing_day == "indeterminate") {
    unknown <- Map(
      function(day, index, outcome) {
        rlang::expr((!!index | !!outcome) & (!!day$missing | !!day$sentinel))
      },
      decoded,
      index_matches,
      outcome_matches
    )
    unknown <- timing_or_expr(unknown)
    success <- rlang::expr(dplyr::if_else(!!success, TRUE, dplyr::if_else(!!unknown, NA, FALSE)))
  }
  rlang::expr(dplyr::if_else(!(!!index_present) | !(!!outcome_present), FALSE, !!success))
}

timing_relation_check <- function(outcome_day, matched, index_day, relation, window) {
  comparison <- switch(
    relation,
    on_or_after = rlang::expr(!!outcome_day >= !!index_day),
    after = rlang::expr(!!outcome_day > !!index_day),
    before = rlang::expr(!!outcome_day < !!index_day),
    same_day = rlang::expr(!!outcome_day == !!index_day),
    within_days = rlang::expr(
      !!outcome_day - !!index_day >= 0 &
        !!outcome_day - !!index_day <= !!window
    )
  )
  rlang::expr(!!matched & !!comparison)
}

timing_or_expr <- function(terms) {
  rlang::expr(dplyr::coalesce(!!reduce_or(terms), FALSE))
}
