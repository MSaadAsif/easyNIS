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
  if (missing(window)) window <- NULL
  arguments <- timing_validate_args(.data, index_pr, outcome_pr, name,
    relation, window, missing_day, system)
  relation <- arguments$relation
  missing_day <- arguments$missing_day
  system <- arguments$system
  index_pr <- arguments$index_pr
  outcome_pr <- arguments$outcome_pr
  data_names <- arguments$data_names
  layout <- timing_layout(data_names, system)
  matched <- timing_matches(.data, layout$procedure_names, index_pr, outcome_pr,
    data_names)
  .data <- matched$data
  temporary_names <- matched$temporary_names
  index_matches <- matched$index_matches
  outcome_matches <- matched$outcome_matches
  days <- timing_days(.data, layout$slots, layout$day_by_slot)
  day_missing <- timing_day_missing(.data, layout$slots, layout$day_by_slot)
  index <- timing_index_days(.data, days, day_missing, index_matches,
    missing_day, data_names, temporary_names)
  .data <- index$data
  temporary_names <- index$temporary_names
  result <- timing_result(days, day_missing, index_matches, outcome_matches,
    index$index_day, relation, window, missing_day)
  eligibility <- code_system_filter(.data, data_names, "PR", system) # nolint: object_usage_linter
  if (!is.null(eligibility)) result <- nis_and_expr(eligibility, result) # nolint: object_usage_linter
  .data <- dplyr::mutate(.data, !!name := !!result)
  dplyr::select(.data, -dplyr::all_of(temporary_names))
}

timing_validate_args <- function(.data, index_pr, outcome_pr, name, relation,
                                 window, missing_day, system) {
  data_names <- nis_names(.data) # nolint: object_usage_linter
  timing_validate_name(name, data_names)
  timing_validate_window(relation, window)
  if (relation == "within_days") window <- as.integer(window)
  index_pr <- normalize_prefixes(index_pr, "index_pr") # nolint: object_usage_linter
  outcome_pr <- normalize_prefixes(outcome_pr, "outcome_pr") # nolint: object_usage_linter
  list(relation = relation, missing_day = missing_day, system = system,
    index_pr = index_pr, outcome_pr = outcome_pr, data_names = data_names)
}

timing_validate_name <- function(name, data_names) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    cli::cli_abort("name must be a single non-empty column name.",
      call = as.call(list(as.name("nis_flag_pr_timing"))))
  }
  if (name %in% data_names) {
    cli::cli_abort("name must not replace an existing column.",
      call = as.call(list(as.name("nis_flag_pr_timing"))))
  }
}

timing_validate_window <- function(relation, window) {
  if (relation == "within_days") {
    if (!timing_window_scalar(window) || !timing_window_range(window) ||
        window != as.integer(window)) {
      cli::cli_abort("window must be a single non-negative integer for within_days.",
        call = as.call(list(as.name("nis_flag_pr_timing"))))
    }
  } else if (!is.null(window)) {
    cli::cli_abort("window must be NULL unless relation is within_days.",
      call = as.call(list(as.name("nis_flag_pr_timing"))))
  }
}

timing_window_scalar <- function(window) {
  is.numeric(window) && length(window) == 1L && !is.na(window) &&
    is.finite(window)
}

timing_window_range <- function(window) {
  window >= 0 && window <= .Machine$integer.max
}

timing_layout <- function(data_names, system) {
  stem <- if (system == "icd10") "I10_PR" else "PR"
  procedure_names <- grep(paste0("^", stem, "[0-9]+$"), data_names, value = TRUE)
  day_names <- grep("^PRDAY[0-9]+$", data_names, value = TRUE)
  timing_validate_layout(procedure_names, day_names, stem, system)
  slots <- as.integer(sub(paste0("^", stem), "", procedure_names))
  order_slots <- order(slots)
  procedure_names <- procedure_names[order_slots]
  slots <- slots[order_slots]
  day_by_slot <- stats::setNames(day_names,
    as.character(as.integer(sub("^PRDAY", "", day_names))))
  list(procedure_names = procedure_names, slots = slots,
    day_by_slot = day_by_slot)
}

timing_validate_layout <- function(procedure_names, day_names, stem, system) {
  if (length(procedure_names) == 0L) {
    cli::cli_abort(paste0("No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} PR columns (",
      stem, "<n>) were found."),
      call = as.call(list(as.name("nis_flag_pr_timing"))))
  }
  if (length(day_names) == 0L) {
    cli::cli_abort("No PRDAY<n> columns were found for procedure timing.",
      call = as.call(list(as.name("nis_flag_pr_timing"))))
  }
}

timing_matches <- function(data, procedure_names, index_pr, outcome_pr,
                           data_names) {
  is_frame <- is.data.frame(data)
  match_slot <- if (is_frame) frame_match else nis_sql_match # nolint: object_usage_linter
  index <- lapply(procedure_names, match_slot, prefix = index_pr)
  outcome <- lapply(procedure_names, match_slot, prefix = outcome_pr)
  count <- length(index) + length(outcome)
  names <- make.unique(c(data_names, paste0(".easyNIS_pr_timing_match_", seq_len(count))))
  names <- names[length(data_names) + seq_len(count)]
  data <- dplyr::mutate(data, !!!stats::setNames(c(index, outcome), names))
  list(data = data, temporary_names = names,
    index_matches = rlang::syms(names[seq_along(index)]),
    outcome_matches = rlang::syms(names[length(index) + seq_along(outcome)]))
}

timing_days <- function(data, slots, day_by_slot) {
  lapply(slots, function(slot) {
    day_name <- unname(day_by_slot[as.character(slot)])
    if (length(day_name) == 0L || is.na(day_name)) rlang::expr(NA_real_) else
      nis_numeric_value_expr(day_name) # nolint: object_usage_linter
  })
}

timing_day_missing <- function(data, slots, day_by_slot) {
  lapply(slots, function(slot) {
    day_name <- unname(day_by_slot[as.character(slot)])
    if (length(day_name) == 0L || is.na(day_name)) rlang::expr(TRUE) else
      nis_is_missing_expr(data, day_name) # nolint: object_usage_linter
  })
}

timing_valid_day <- function(day, missing) {
  rlang::expr(dplyr::if_else(!!missing, NA_real_,
    dplyr::if_else(!!day >= 0, !!day, NA_real_)))
}

timing_index_days <- function(data, days, day_missing, index_matches,
                              missing_day, data_names, temporary_names) {
  index_days <- Map(function(day, missing, matched) {
    day <- timing_valid_day(day, missing)
    if (missing_day == "assume_same_day") {
      rlang::expr(dplyr::if_else(!!matched, dplyr::coalesce(!!day, 0), NA_real_))
    } else {
      rlang::expr(dplyr::if_else(!!matched, !!day, NA_real_))
    }
  }, days, day_missing, index_matches)
  index_candidates <- paste0(".easyNIS_pr_timing_index_day_", seq_along(index_days))
  all_names <- make.unique(c(data_names, temporary_names, index_candidates))
  index_names <- all_names[length(data_names) + length(temporary_names) +
    seq_along(index_candidates)]
  data <- dplyr::mutate(data, !!!stats::setNames(index_days, index_names))
  index_symbols <- rlang::syms(index_names)
  valid <- timing_or_expr(lapply(index_symbols, function(day) rlang::expr(!is.na(!!day))))
  min_day <- rlang::expr(pmin(!!!index_symbols, na.rm = TRUE))
  min_name <- make.unique(c(data_names, temporary_names, index_names,
    ".easyNIS_pr_timing_min_index_day"))
  min_name <- min_name[[length(min_name)]]
  data <- dplyr::mutate(data, !!min_name := dplyr::if_else(!!valid, !!min_day, NA_real_))
  list(data = data, index_day = rlang::sym(min_name),
    temporary_names = c(temporary_names, index_names, min_name))
}

timing_result <- function(days, day_missing, index_matches, outcome_matches,
                          index_day, relation, window, missing_day) {
  index_present <- timing_or_expr(index_matches)
  outcome_present <- timing_or_expr(outcome_matches)
  unknown <- function(day, missing, matched) {
    rlang::expr(!!matched & (!!missing | !!day < 0))
  }
  missing_match <- timing_or_expr(c(
    Map(unknown, days, day_missing, index_matches),
    Map(unknown, days, day_missing, outcome_matches)
  ))
  checks <- lapply(seq_along(days), function(i) {
    timing_relation_check(days[[i]], day_missing[[i]], outcome_matches[[i]],
      index_day, relation, window, missing_day)
  })
  success <- timing_or_expr(checks)
  timing_result_expr(index_present, outcome_present, success, missing_match,
    missing_day)
}

timing_relation_check <- function(day, missing, matched, index_day, relation,
                                  window, missing_day) {
  outcome_day <- timing_valid_day(day, missing)
  if (missing_day == "assume_same_day") {
    outcome_day <- rlang::expr(dplyr::coalesce(!!outcome_day, 0))
  }
  comparison <- switch(relation,
    on_or_after = rlang::expr(!!outcome_day >= !!index_day),
    after = rlang::expr(!!outcome_day > !!index_day),
    before = rlang::expr(!!outcome_day < !!index_day),
    same_day = rlang::expr(!!outcome_day == !!index_day),
    within_days = rlang::expr(!!outcome_day - !!index_day >= 0 &
      !!outcome_day - !!index_day <= !!window))
  rlang::expr(!!matched & !!comparison)
}

timing_result_expr <- function(index_present, outcome_present, success,
                               missing_match, missing_day) {
  if (missing_day == "indeterminate") {
    return(rlang::expr(dplyr::if_else(
      !(!!index_present) | !(!!outcome_present), FALSE,
      dplyr::if_else(dplyr::coalesce(!!success, FALSE), TRUE,
        dplyr::if_else(!!missing_match, NA, FALSE))
    )))
  }
  rlang::expr(dplyr::if_else(
    !(!!index_present) | !(!!outcome_present), FALSE,
    dplyr::coalesce(!!success, FALSE)
  ))
}

timing_or_expr <- function(terms) {
  rlang::expr(dplyr::coalesce(!!reduce_or(terms), FALSE))
}
