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
#' @param .data A data frame or lazy Arrow query.
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
  if (name %in% names(.data)) {
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
  procedure_names <- grep(paste0("^", stem, "[0-9]+$"), names(.data), value = TRUE)
  day_names <- grep("^PRDAY[0-9]+$", names(.data), value = TRUE)
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
  projection <- if (is_frame) NULL else
    dplyr::select(.data, dplyr::everything())$selected_columns
  match_slot <- if (is_frame) {
    function(prefixes, column) frame_match(prefixes, column)
  } else {
    function(prefixes, column) arrow_match(prefixes, projection[column])
  }
  index_matches <- lapply(procedure_names, match_slot, prefixes = index_pr)
  outcome_matches <- lapply(procedure_names, match_slot, prefixes = outcome_pr)
  if (!is_frame) {
    temporary_names <- make.unique(c(names(.data), paste0(
      ".easyNIS_pr_timing_match_",
      seq_len(length(index_matches) + length(outcome_matches))
    )))[length(names(.data)) + seq_len(length(index_matches) + length(outcome_matches))]
    match_columns <- stats::setNames(c(index_matches, outcome_matches), temporary_names)
    # Arrow expressions must be assigned directly before shared rlang
    # expressions can refer to their result columns.
    .data <- dplyr::mutate(.data, !!!match_columns)
    index_matches <- rlang::syms(temporary_names[seq_along(index_matches)])
    outcome_matches <- rlang::syms(temporary_names[length(index_matches) +
      seq_along(outcome_matches)])
  }
  days <- lapply(slots, function(slot) {
    day_name <- unname(day_by_slot[as.character(slot)])
    if (length(day_name) == 0L || is.na(day_name)) rlang::expr(NA_real_) else
      rlang::sym(day_name)
  })

  valid_day <- function(day) rlang::expr(dplyr::if_else(!!day >= 0, !!day, NA_real_))
  index_days <- Map(function(day, matched) {
    if (missing_day == "assume_same_day") {
      rlang::expr(dplyr::if_else(!!matched,
        dplyr::coalesce(!!valid_day(day), 0), NA_real_))
    } else {
      rlang::expr(dplyr::if_else(!!matched, !!valid_day(day), NA_real_))
    }
  }, days, index_matches)
  index_day <- Reduce(timing_min_expr, index_days)
  index_present <- timing_or_expr(index_matches)
  outcome_present <- timing_or_expr(outcome_matches)
  missing_match <- timing_or_expr(c(
    Map(function(day, matched) rlang::expr(!!matched & (is.na(!!day) | !!day < 0)),
      days, index_matches),
    Map(function(day, matched) rlang::expr(!!matched & (is.na(!!day) | !!day < 0)),
      days, outcome_matches)
  ))

  checks <- Map(function(day, matched) {
    outcome_day <- if (missing_day == "assume_same_day") {
      rlang::expr(dplyr::coalesce(!!valid_day(day), 0))
    } else {
      valid_day(day)
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
  }, days, outcome_matches)
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
  eligibility <- code_system_filter(names(.data), "PR", system)
  if (!is.null(eligibility)) {
    result <- rlang::expr((!!eligibility) & (!!result))
  }
  .data <- dplyr::mutate(.data, !!name := !!result)
  if (is_frame) .data else dplyr::select(.data, -dplyr::all_of(temporary_names))
}

timing_or_expr <- function(terms) {
  Reduce(function(left, right) rlang::expr(dplyr::coalesce((!!left) | (!!right), FALSE)),
    terms)
}

timing_min_expr <- function(left, right) {
  rlang::expr(dplyr::if_else(is.na(!!left), !!right,
    dplyr::if_else(is.na(!!right), !!left,
      dplyr::if_else(!!left <= !!right, !!left, !!right))))
}
