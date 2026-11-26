#' Add diagnosis position flags
#'
#' Adds flags for a diagnosis prefix in the principal position, secondary
#' positions only, and any position. Prefix matching and code-system eligibility
#' follow [nis_flag_dx()].
#'
#' @template dot-data
#' @param code Non-missing character vector of diagnosis prefixes.
#' @param name Base name for the added columns. The function adds
#'   `<name>_principal`, `<name>_secondary_only`, and `<name>_any`.
#' @param system Code system of the diagnosis slots: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#'
#' @return `.data` with three logical diagnosis-position columns.
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019))
#' nis_flag_dx_position(nis, "I50", name = "heart_failure")
nis_flag_dx_position <- function(.data, code, name = "dx", system = c("icd10", "icd9")) {
  system <- match.arg(system)
  if (!is.character(name) || length(name) != 1L || is.na(name) || !grepl("^\\.?[A-Za-z][A-Za-z0-9._]*$", name)) {
    cli::cli_abort("`name` must be one syntactic column-name prefix.")
  }
  output_names <- dx_position_names(name)
  columns <- nis_names(.data)
  if (!identical(unname(output_names), nis_internal_names(.data, columns, unname(output_names)))) {
    cli::cli_abort("The diagnosis-position output columns must not replace existing columns.")
  }
  dx_add_position_flags(.data, columns, code, system, output_names)
}

dx_position_names <- function(prefix) {
  positions <- c("principal", "secondary_only", "any")
  stats::setNames(paste(prefix, positions, sep = "_"), positions)
}

dx_add_position_flags <- function(data, columns, code, system, output_names) {
  rule <- nis_prefix_rule(normalize_prefixes(code))
  principal <- nis_flag_slot_names(columns, "DX", system, "principal")
  slots <- nis_flag_slot_names(columns, "DX", system, "any")
  eligibility <- code_system_filter(data, columns, "DX", system)
  flags <- lapply(list(principal, slots), function(slots) {
    nis_in_code_system(nis_code_match(rule, data, slots), eligibility)
  })
  names(flags) <- unname(output_names[c("principal", "any")])
  secondary <- rlang::expr(
    !!rlang::sym(output_names[["any"]]) &
      !(!!rlang::sym(output_names[["principal"]]))
  )
  flags[[output_names[["secondary_only"]]]] <- secondary
  dplyr::mutate(data, !!!flags)
}

#' Summarize diagnosis-position sensitivity
#'
#' Summarizes unweighted and weighted presentation counts and outcome rates for
#' principal, secondary-only, and any-position diagnosis flags. These are
#' descriptive point estimates, not design-based survey estimates; use
#' [nis_design()] when standard errors are needed. Small cells must go through
#' [nis_suppress()] before reporting under the HCUP Data Use Agreement, which
#' prohibits reporting cells of 1–10.
#'
#' @template dot-data
#' @param code Non-missing character vector of diagnosis prefixes.
#' @param system Code system of the diagnosis slots: `"icd10"` (default) or
#'   `"icd9"` (experimental, NIS 2012 to Q3 2015).
#' @param weight_var Name of the discharge weight column. Defaults to `DISCWT`.
#' @param outcomes Outcome columns to summarize. By default, `DIED` and
#'   `ELECTIVE` are included when present and absent defaults are skipped.
#'
#' @return A collected tibble with one row per presentation and unweighted and
#'   weighted counts, shares of all prefix-positive presentations, and rates
#'   for requested outcomes. The principal presentation is a strict subset of
#'   any-position cases, so Cohen's kappa is not meaningful here. Existing input
#'   groups are ignored: summaries describe the full input. Empty inputs return
#'   zero counts and missing shares and rates. Missing weights are omitted from
#'   weighted sums; missing outcomes are excluded from that outcome's denominator.
#'   Rates with zero denominators are missing.
#' @family cohort-definition
#' @seealso [Code transitions and sensitivity](articles/code-transitions.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019))
#' nis_dx_sensitivity(nis, "I50")
nis_dx_sensitivity <- function(
  .data,
  code,
  system = c("icd10", "icd9"),
  weight_var = "DISCWT",
  outcomes = c("DIED", "ELECTIVE")
) {
  system <- match.arg(system)
  outcomes_were_supplied <- !missing(outcomes)
  dx_validate_weight(weight_var)
  columns <- nis_names(.data)
  outcomes <- dx_validate_outcomes(outcomes, columns, outcomes_were_supplied)
  if (!weight_var %in% columns) {
    cli::cli_abort("Weight column {.val {weight_var}} is missing from `.data`.")
  }

  flags <- dx_position_names(".nis_dx")
  flags[] <- nis_internal_names(.data, columns, unname(flags))
  data <- dx_add_position_flags(dplyr::ungroup(.data), columns, code, system, flags)

  summary_flags <- dx_summary_names(nis_names(data), flags)
  summary_exprs <- dx_summary_exprs(data, flags, outcomes, weight_var, summary_flags)
  summary <- dplyr::summarise(data, !!!summary_exprs) |>
    nis_collect() |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ dplyr::coalesce(.x, 0)))
  dx_summary_result(summary, summary_flags, outcomes)
}

dx_validate_weight <- function(weight_var) {
  if (!is.character(weight_var) || length(weight_var) != 1L || is.na(weight_var) || !nzchar(weight_var)) {
    cli::cli_abort("`weight_var` must be one column name.", call = rlang::caller_call())
  }
}

dx_validate_outcomes <- function(outcomes, columns, supplied) {
  if (!is.character(outcomes) || anyNA(outcomes) || !all(nzchar(outcomes)) || anyDuplicated(outcomes)) {
    cli::cli_abort("`outcomes` must be a character vector of unique column names.", call = rlang::caller_call())
  }
  absent <- setdiff(outcomes, columns)
  if (supplied && length(absent) > 0L) {
    cli::cli_abort("Missing requested outcome column{?s}: {.val {absent}}.", call = rlang::caller_call())
  }
  intersect(outcomes, columns)
}

dx_summary_names <- function(columns, flags) {
  prefix <- ".nis_dx_summary_"
  while (any(startsWith(tolower(columns), tolower(prefix)))) {
    prefix <- paste0(prefix, "_")
  }
  stats::setNames(paste0(prefix, seq_along(flags)), names(flags))
}

dx_summary_exprs <- function(data, flags, outcomes, weight_var, summary_flags) {
  missing_weight <- nis_is_missing_expr(data, weight_var)
  weight <- rlang::expr(dplyr::if_else(!!missing_weight, 0, !!rlang::sym(weight_var)))
  known_outcomes <- lapply(outcomes, function(outcome) {
    rlang::expr(!(!!nis_is_missing_expr(data, outcome)))
  })
  Reduce(
    c,
    lapply(names(flags), function(presentation) {
      dx_flag_exprs(flags[[presentation]], outcomes, known_outcomes, weight, summary_flags[[presentation]])
    })
  )
}

dx_flag_exprs <- function(flag, outcomes, known_outcomes, weight, summary_flag) {
  selected <- rlang::sym(flag)
  expressions <- list(
    rlang::expr(sum(!!selected, na.rm = TRUE)),
    dx_weighted_count(selected, weight)
  )
  names(expressions) <- paste0(summary_flag, c("_n", "_weighted"))
  for (index in seq_along(outcomes)) {
    expressions <- c(
      expressions,
      dx_outcome_exprs(selected, outcomes[[index]], known_outcomes[[index]], weight, paste0(summary_flag, "_", index))
    )
  }
  expressions
}

dx_weighted_count <- function(selected, weight) {
  rlang::expr(sum(dplyr::if_else(!!selected, !!weight, 0), na.rm = TRUE))
}

dx_outcome_exprs <- function(selected, outcome, known, weight, summary_name) {
  denominator <- rlang::expr(!!selected & !!known)
  events <- rlang::expr(!!denominator & !!rlang::sym(outcome) == 1)
  expressions <- list(
    rlang::expr(sum(!!denominator, na.rm = TRUE)),
    rlang::expr(sum(!!events, na.rm = TRUE)),
    dx_weighted_count(denominator, weight),
    dx_weighted_count(events, weight)
  )
  names(expressions) <- paste0(summary_name, c("_n", "_events", "_weighted_n", "_weighted_events"))
  expressions
}

dx_summary_result <- function(summary, flags, outcomes) {
  any_n <- summary[[paste0(flags[["any"]], "_n")]][[1L]]
  any_weighted <- summary[[paste0(flags[["any"]], "_weighted")]][[1L]]
  result <- dplyr::tibble(
    presentation = c("principal", "secondary_only", "any"),
    n_unweighted = unname(vapply(
      flags,
      function(flag) {
        summary[[paste0(flag, "_n")]][[1L]]
      },
      numeric(1)
    )),
    n_weighted = unname(vapply(
      flags,
      function(flag) {
        summary[[paste0(flag, "_weighted")]][[1L]]
      },
      numeric(1)
    ))
  )
  result$pct_of_any_unweighted <- if (any_n > 0) {
    result$n_unweighted / any_n * 100
  } else {
    NA_real_
  }
  result$pct_of_any_weighted <- if (any_weighted > 0) {
    result$n_weighted / any_weighted * 100
  } else {
    NA_real_
  }
  for (index in seq_along(outcomes)) {
    result <- dx_append_rates(result, summary, flags, outcomes[[index]], index)
  }
  result
}

dx_append_rates <- function(result, summary, flags, outcome, index) {
  result[[paste0(outcome, "_rate_unweighted")]] <- dx_rate_vector(
    summary,
    flags,
    index,
    FALSE
  )
  result[[paste0(outcome, "_rate_weighted")]] <- dx_rate_vector(
    summary,
    flags,
    index,
    TRUE
  )
  result
}

dx_rate_vector <- function(summary, flags, outcome, weighted) {
  suffix <- if (weighted) "_weighted" else ""
  events <- if (weighted) "_weighted_events" else "_events"
  unname(vapply(
    flags,
    function(flag) {
      denominator <- summary[[paste0(flag, "_", outcome, suffix, "_n")]][[1L]]
      if (denominator == 0) {
        NA_real_
      } else {
        summary[[paste0(flag, "_", outcome, events)]][[1L]] / denominator
      }
    },
    numeric(1)
  ))
}
