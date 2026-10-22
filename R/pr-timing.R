#' Flag procedure timing relative to an index procedure
#'
#' Compares procedure slots with the correspondingly numbered PRDAY values.
#' The earliest valid index day is used when the index procedure occurs in
#' multiple slots. A slot matching both prefix sets counts as both procedures.
#' Prefixes follow the normalization and matching rules of [nis_flag_pr()].
#' Negative days (including HCUP sentinel values) and missing days are unknown.
#' If either procedure is absent, the result is FALSE. Otherwise, any outcome
#' with a known day satisfying the relation returns TRUE. If none does and a
#' matching procedure has an unknown day, exclude returns FALSE,
#' assume_same_day treats that day as 0, and indeterminate returns NA.
#'
#' on_or_after tests outcome day >= earliest index day; after tests >; before
#' tests <; same_day tests equality. within_days tests whether the outcome is
#' from 0 through window days after the earliest index day, inclusive.
#'
#' @param .data A data frame or lazy DuckDB query.
#' @param index_pr Character vector of index procedure code prefixes.
#' @param outcome_pr Character vector of outcome procedure code prefixes.
#' @param name Single name for the new logical flag.
#' @param relation Timing relation: on_or_after, after, before, same_day, or
#'   within_days.
#' @param window Required non-negative integer for within_days; otherwise NULL.
#' @param missing_day How to handle unknown days: exclude returns FALSE,
#'   assume_same_day uses day 0, and indeterminate returns NA unless a
#'   determinate match is TRUE.
#' @param system Code system: icd10 uses I10_PR<n>; icd9 uses PR<n>.
#'
#' @return .data with the logical column named by name.
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
#' @examples
#' toy <- data.frame(I10_PR1 = c("02UG0JZ", "0JH604Z"), PRDAY1 = c(0L, 1L))
#' nis_flag_pr_timing(toy, "02UG0", "0JH60")
nis_flag_pr_timing <- function(.data, index_pr, outcome_pr,
                               name = "outcome_post_index",
                               relation = c("on_or_after", "after", "before",
                                 "same_day", "within_days"),
                               window = NULL,
                               missing_day = c("exclude", "assume_same_day",
                                 "indeterminate"),
                               system = c("icd10", "icd9")) {
  relation <- match.arg(relation)
  missing_day <- match.arg(missing_day)
  system <- match.arg(system)
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    cli::cli_abort("name must be a single non-empty column name.")
  }
  data_names <- nis_names(.data) # nolint: object_usage_linter
  if (name %in% data_names) {
    cli::cli_abort("name must not replace an existing column.")
  }
  if (relation == "within_days") {
    if (!is.numeric(window) || length(window) != 1L || is.na(window) ||
        !is.finite(window) || window < 0 || window > .Machine$integer.max ||
        window != as.integer(window)) {
      cli::cli_abort("window must be a single non-negative integer for within_days.")
    }
    window <- as.integer(window)
  } else if (!is.null(window)) {
    cli::cli_abort("window must be NULL unless relation is within_days.")
  }
  index_pr <- normalize_prefixes(index_pr, "index_pr")
  outcome_pr <- normalize_prefixes(outcome_pr, "outcome_pr")

  stem <- if (system == "icd10") "I10_PR" else "PR"
  procedure_names <- grep(paste0("^", stem, "[0-9]+$"), data_names, value = TRUE)
  day_names <- grep("^PRDAY[0-9]+$", data_names, value = TRUE)
  if (length(procedure_names) == 0L) {
    cli::cli_abort(paste0("No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} PR columns (",
      stem, "<n>) were found."))
  }
  if (length(day_names) == 0L) {
    cli::cli_abort("No PRDAY<n> columns were found for procedure timing.")
  }
  slots <- as.integer(sub(paste0("^", stem), "", procedure_names))
  order_slots <- order(slots)
  procedure_names <- procedure_names[order_slots]
  slots <- slots[order_slots]
  day_by_slot <- stats::setNames(day_names,
    as.character(as.integer(sub("^PRDAY", "", day_names))))
  is_frame <- is.data.frame(.data)
  match_slot <- if (is_frame) {
    function(prefixes, column) frame_match(prefixes, column)
  } else {
    function(prefixes, column) {
      nis_sql_match(prefixes, column) # nolint: object_usage_linter
    }
  }
  index_matches <- lapply(procedure_names, match_slot, prefixes = index_pr)
  outcome_matches <- lapply(procedure_names, match_slot, prefixes = outcome_pr)
  temporary_names <- make.unique(c(data_names, paste0(
    ".easyNIS_pr_timing_match_", seq_len(length(index_matches) + length(outcome_matches))
  )))[length(data_names) + seq_len(length(index_matches) + length(outcome_matches))]
  .data <- dplyr::mutate(.data,
    !!!stats::setNames(c(index_matches, outcome_matches), temporary_names))
  index_matches <- rlang::syms(temporary_names[seq_along(index_matches)])
  outcome_matches <- rlang::syms(temporary_names[length(index_matches) +
    seq_along(outcome_matches)])
  days <- lapply(slots, function(slot) {
    day_name <- unname(day_by_slot[as.character(slot)])
    if (length(day_name) == 0L || is.na(day_name)) rlang::expr(NA_real_) else
      rlang::sym(day_name)
  })
  day_missing <- lapply(slots, function(slot) {
    day_name <- unname(day_by_slot[as.character(slot)])
    if (length(day_name) == 0L || is.na(day_name)) {
      rlang::expr(TRUE)
    } else {
      nis_is_missing_expr(.data, day_name) # nolint: object_usage_linter
    }
  })
  valid_day <- function(day, missing) {
    rlang::expr(dplyr::if_else(
      !!missing, NA_real_, dplyr::if_else(!!day >= 0, !!day, NA_real_)))
  }
  index_days <- Map(function(day, missing, matched) {
    day <- valid_day(day, missing)
    if (missing_day == "assume_same_day") {
      rlang::expr(dplyr::if_else(!!matched,
        dplyr::coalesce(!!day, 0), NA_real_))
    } else {
      rlang::expr(dplyr::if_else(!!matched, !!day, NA_real_))
    }
  }, days, day_missing, index_matches)
  index_candidates <- paste0(
    ".easyNIS_pr_timing_index_day_", seq_along(index_days)
  )
  index_names <- make.unique(c(data_names, temporary_names, index_candidates))[
    length(data_names) + length(temporary_names) + seq_along(index_candidates)
  ]
  .data <- dplyr::mutate(.data, !!!stats::setNames(index_days, index_names))
  temporary_names <- c(temporary_names, index_names)
  index_days <- rlang::syms(index_names)
  index_valid <- timing_or_expr(lapply(index_days, function(day) {
    rlang::expr(!is.na(!!day))
  }))
  min_index_day <- rlang::expr(pmin(!!!index_days, na.rm = TRUE))
  min_name <- make.unique(c(data_names, temporary_names, index_names,
    ".easyNIS_pr_timing_min_index_day"))[
    length(data_names) + length(temporary_names) + length(index_names) + 1L
  ]
  .data <- dplyr::mutate(.data, !!min_name := dplyr::if_else(
    !!index_valid, !!min_index_day, NA_real_))
  temporary_names <- c(temporary_names, min_name)
  index_day <- rlang::sym(min_name)
  index_present <- timing_or_expr(index_matches)
  outcome_present <- timing_or_expr(outcome_matches)
  unknown_day_match <- function(day, missing, matched) {
    rlang::expr(!!matched & (!!missing | !!day < 0))
  }
  missing_match <- timing_or_expr(c(
    Map(unknown_day_match, days, day_missing, index_matches),
    Map(unknown_day_match, days, day_missing, outcome_matches)
  ))

  checks <- Map(function(day, missing, matched) {
    outcome_day <- valid_day(day, missing)
    if (missing_day == "assume_same_day") {
      outcome_day <- rlang::expr(dplyr::coalesce(!!outcome_day, 0))
    }
    comparison <- switch(relation,
      on_or_after = rlang::expr(!!outcome_day >= !!index_day),
      after = rlang::expr(!!outcome_day > !!index_day),
      before = rlang::expr(!!outcome_day < !!index_day),
      same_day = rlang::expr(!!outcome_day == !!index_day),
      within_days = rlang::expr(!!outcome_day - !!index_day >= 0 &
        !!outcome_day - !!index_day <= !!window)
    )
    rlang::expr(!!matched & !!comparison)
  }, days, day_missing, outcome_matches)
  success <- timing_or_expr(checks)
  if (missing_day == "indeterminate") {
    result <- rlang::expr(dplyr::if_else(
      !(!!index_present) | !(!!outcome_present), FALSE,
      dplyr::if_else(dplyr::coalesce(!!success, FALSE), TRUE,
        dplyr::if_else(!!missing_match, NA, FALSE))
    ))
  } else {
    result <- rlang::expr(dplyr::if_else(
      !(!!index_present) | !(!!outcome_present), FALSE,
      dplyr::coalesce(!!success, FALSE)
    ))
  }
  eligibility <- code_system_filter(data_names, "PR", system)
  if (!is.null(eligibility)) {
    result <- nis_and_expr(eligibility, result) # nolint: object_usage_linter
  }
  .data <- dplyr::mutate(.data, !!name := !!result)
  dplyr::select(.data, -dplyr::all_of(temporary_names))
}

timing_or_expr <- function(terms) {
  rlang::expr(dplyr::coalesce(!!reduce_or(terms), FALSE))
}
