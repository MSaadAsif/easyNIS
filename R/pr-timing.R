#' Flag procedure timing relative to an index procedure
#'
#' Compares procedure slots with the correspondingly numbered PRDAY values.
#' The earliest valid index day is used when the index procedure occurs in
#' multiple slots. A slot matching both definitions counts as both procedures.
#' Definitions follow the prefix, regular expression, and exact exclusion rules
#' of [nis_flag_pr()]; timing compares slots within the same code system.
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
#' @param index_pr Code definition for the index procedure, as in [nis_flag_pr()].
#' @param outcome_pr Code definition for the outcome procedure, as in [nis_flag_pr()].
#' @param name Single name for the new logical flag.
#' @param relation Timing relation: on_or_after, after, before, same_day, or
#'   within_days.
#' @param window Required non-negative integer for within_days; otherwise NULL.
#' @param missing_day How to handle unknown days: exclude returns FALSE,
#'   assume_same_day uses day 0, and indeterminate returns NA unless a
#'   determinate match is TRUE.
#' @param system Code system: icd10 uses I10_PR followed by a slot number;
#'   icd9 uses PR followed by a slot number. With `system = "both"`, supply
#'   named `icd9` and `icd10` definitions for each procedure.
#'
#' @return .data with the logical column named by name.
#' @family cohort-definition
#' @seealso [Defining cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).
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
  system = c("icd10", "icd9", "both")
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
  if (system == "both") {
    return(timing_flag_both(.data, index_pr, outcome_pr, name, relation, window, missing_day, error_call))
  }
  timing_flag_system(.data, index_pr, outcome_pr, name, relation, window, missing_day, system, error_call)
}

timing_flag_both <- function(data, index_pr, outcome_pr, name, relation, window, missing_day, error_call) {
  index_pr <- nis_mixed_flag_definition(index_pr)
  outcome_pr <- nis_mixed_flag_definition(outcome_pr)
  systems <- c("icd9", "icd10")
  flags <- nis_internal_names(data, c(nis_names(data), name), paste0(".nis_timing_", systems))
  for (i in seq_along(systems)) {
    system <- systems[[i]]
    data <- timing_flag_system(
      data,
      index_pr[[system]],
      outcome_pr[[system]],
      flags[[i]],
      relation,
      window,
      missing_day,
      system,
      error_call
    )
  }
  data |>
    dplyr::mutate(!!name := !!rlang::sym(flags[[1L]]) | !!rlang::sym(flags[[2L]])) |>
    dplyr::select(-dplyr::all_of(flags))
}

timing_flag_system <- function(data, index_pr, outcome_pr, name, relation, window, missing_day, system, error_call) {
  rules <- list(normalize_flag_definition(index_pr, "index_pr"), normalize_flag_definition(outcome_pr, "outcome_pr"))
  nis_validate_flag_rules(rules)
  data_names <- nis_names(data)
  layout <- nis_procedure_slots(data_names, system, error_call)
  if (!layout$has_days) {
    cli::cli_abort("No PRDAY<n> columns were found for procedure timing.", call = error_call)
  }

  reserved <- c(data_names, name)
  slots <- timing_slot_fields(data, layout, rules, missing_day, reserved)
  min_name <- nis_internal_names(data, c(reserved, names(slots$fields)), ".nis_timing_min_index_day")
  earliest <- timing_index_day(slots$days, slots$index)
  result <- timing_result(slots, rlang::sym(min_name), relation, window, missing_day)
  eligibility <- code_system_filter(data, data_names, "PR", system)
  result <- nis_in_code_system(result, eligibility)
  data |>
    dplyr::mutate(!!!slots$fields) |>
    dplyr::mutate(!!min_name := !!earliest) |>
    dplyr::mutate(!!name := !!result) |>
    dplyr::select(-dplyr::all_of(c(names(slots$fields), min_name)))
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

timing_slot_fields <- function(data, layout, rules, missing_day, reserved) {
  positions <- seq_along(layout$procedure)
  candidates <- lapply(c("index", "outcome", "day"), function(field) {
    paste0(".nis_timing_", field, "_", positions)
  })
  aliases <- nis_internal_names(data, reserved, unlist(candidates, use.names = FALSE))
  matches <- lapply(rules, function(rule) {
    lapply(layout$procedure, function(column) nis_code_match(rule, data, column))
  })
  days <- lapply(layout$day, function(column) {
    day <- nis_procedure_day(column, data)$usable
    if (missing_day == "assume_same_day") rlang::expr(dplyr::coalesce(!!day, 0)) else day
  })
  list(
    fields = stats::setNames(c(matches[[1L]], matches[[2L]], days), aliases),
    index = rlang::syms(aliases[positions]),
    outcome = rlang::syms(aliases[length(positions) + positions]),
    days = rlang::syms(aliases[2L * length(positions) + positions])
  )
}

timing_index_day <- function(days, index_matches) {
  candidates <- Map(
    function(day, matched) {
      rlang::expr(dplyr::case_when(!!matched ~ !!day))
    },
    days,
    index_matches
  )
  rlang::expr(pmin(!!!candidates, na.rm = TRUE))
}

timing_result <- function(slots, index_day, relation, window, missing_day) {
  checks <- Map(
    function(day, matched) {
      timing_relation_check(day, matched, index_day, relation, window)
    },
    slots$days,
    slots$outcome
  )
  success <- timing_or_expr(checks)
  if (missing_day != "indeterminate") {
    return(success)
  }
  index_present <- timing_or_expr(slots$index)
  outcome_present <- timing_or_expr(slots$outcome)
  unknown <- Map(
    function(day, index, outcome) rlang::expr((!!index | !!outcome) & is.na(!!day)),
    slots$days,
    slots$index,
    slots$outcome
  )
  rlang::expr(dplyr::case_when(
    !!success ~ TRUE,
    !!index_present & !!outcome_present & !!timing_or_expr(unknown) ~ NA,
    .default = FALSE
  ))
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
  # A variadic maximum avoids a deeply nested chain of SQL OR expressions.
  rlang::expr(dplyr::coalesce(as.logical(pmax(!!!terms, na.rm = TRUE)), FALSE))
}
