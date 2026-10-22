#' Add diagnosis position flags
#'
#' Adds flags for a diagnosis prefix in the principal position, secondary
#' positions only, and any position. Prefix matching and code-system eligibility
#' follow [nis_flag_dx()].
#'
#' @param .data A data frame or lazy DuckDB query.
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
nis_flag_dx_position <- function(.data, code, name = "dx",
                                 system = c("icd10", "icd9")) {
  system <- match.arg(system)
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !grepl("^\\.?[A-Za-z][A-Za-z0-9._]*$", name)) {
    cli::cli_abort("`name` must be one syntactic column-name prefix.")
  }
  output_names <- paste0(name, c("_principal", "_secondary_only", "_any"))
  if (any(output_names %in% nis_names(.data))) { # nolint: object_usage_linter
    cli::cli_abort("The diagnosis-position output columns must not replace existing columns.")
  }

  principal_name <- output_names[[1L]]
  any_name <- output_names[[3L]]
  add_flag <- function(data, flag_name, position) {
    arguments <- c(list(data), stats::setNames(list(code), flag_name),
      list(position = position, system = system))
    do.call(nis_flag_dx, arguments)
  }
  .data <- add_flag(.data, principal_name, "principal")
  .data <- add_flag(.data, any_name, "any")
  dplyr::mutate(.data,
    !!output_names[[2L]] := .data[[any_name]] & !.data[[principal_name]])
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
#' @param .data A data frame or lazy DuckDB query.
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
#'   any-position cases, so Cohen's kappa is not meaningful here.
#' @family cohort-definition
#' @seealso [Code transitions and sensitivity](articles/code-transitions.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019))
#' nis_dx_sensitivity(nis, "I50")
nis_dx_sensitivity <- function(.data, code, system = c("icd10", "icd9"),
                               weight_var = "DISCWT",
                               outcomes = c("DIED", "ELECTIVE")) {
  system <- match.arg(system)
  outcomes_were_supplied <- !missing(outcomes)
  if (!is.character(weight_var) || length(weight_var) != 1L ||
      is.na(weight_var) || !nzchar(weight_var)) {
    cli::cli_abort("`weight_var` must be one column name.")
  }
  if (!is.character(outcomes) || anyNA(outcomes) || any(!nzchar(outcomes)) ||
      anyDuplicated(outcomes)) {
    cli::cli_abort("`outcomes` must be a character vector of unique column names.")
  }
  absent_outcomes <- setdiff(outcomes, nis_names(.data)) # nolint: object_usage_linter
  if (outcomes_were_supplied && length(absent_outcomes) > 0L) {
    cli::cli_abort("Missing requested outcome column{?s}: {.val {absent_outcomes}}.")
  }
  outcomes <- intersect(outcomes, nis_names(.data)) # nolint: object_usage_linter
  if (!weight_var %in% nis_names(.data)) { # nolint: object_usage_linter
    cli::cli_abort("Weight column {.val {weight_var}} is missing from `.data`.")
  }

  flags <- c(principal = ".nis_dx_principal",
    secondary_only = ".nis_dx_secondary_only", any = ".nis_dx_any")
  add_position_flags <- function(data) {
    nis_flag_dx_position(data, code, name = ".nis_dx", system = system)
  }
  data <- add_position_flags(.data)

  summary_exprs <- list()
  for (presentation in names(flags)) {
    flag <- flags[[presentation]]
    summary_exprs[[paste0(flag, "_n")]] <- rlang::expr(
      sum(dplyr::coalesce(!!rlang::sym(flag), FALSE))
    )
    summary_exprs[[paste0(flag, "_weighted")]] <- rlang::expr(
      sum(dplyr::if_else(!!rlang::sym(flag), !!rlang::sym(weight_var), 0),
        na.rm = TRUE)
    )
    for (outcome in outcomes) {
      value <- rlang::sym(outcome)
      weight <- rlang::sym(weight_var)
      selected <- rlang::sym(flag)
      summary_exprs[[paste0(flag, "_", outcome, "_n")]] <- rlang::expr(
        sum(!!selected & !is.na(!!value))
      )
      summary_exprs[[paste0(flag, "_", outcome, "_events")]] <- rlang::expr(
        sum(!!selected & !is.na(!!value) & !!value == 1)
      )
      summary_exprs[[paste0(flag, "_", outcome, "_weighted_n")]] <- rlang::expr(
        sum(dplyr::if_else(!!selected & !is.na(!!value), !!weight, 0),
          na.rm = TRUE)
      )
      summary_exprs[[paste0(flag, "_", outcome, "_weighted_events")]] <- rlang::expr(
        sum(dplyr::if_else(!!selected & !is.na(!!value) & !!value == 1,
          !!weight, 0), na.rm = TRUE)
      )
    }
  }
  summary <- dplyr::summarise(data, !!!summary_exprs) |>
    dplyr::collect()

  any_n <- summary[[paste0(flags[["any"]], "_n")]][[1L]]
  any_weighted <- summary[[paste0(flags[["any"]], "_weighted")]][[1L]]
  result <- dplyr::tibble(
    presentation = c("principal", "secondary_only", "any"),
    n_unweighted = unname(vapply(flags, function(flag) {
      summary[[paste0(flag, "_n")]][[1L]]
    }, numeric(1))),
    n_weighted = unname(vapply(flags, function(flag) {
      summary[[paste0(flag, "_weighted")]][[1L]]
    }, numeric(1)))
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
  for (outcome in outcomes) {
    result[[paste0(outcome, "_rate_unweighted")]] <- unname(vapply(flags, function(flag) {
      denominator <- summary[[paste0(flag, "_", outcome, "_n")]][[1L]]
      if (denominator == 0) NA_real_ else
        summary[[paste0(flag, "_", outcome, "_events")]][[1L]] / denominator
    }, numeric(1)))
    result[[paste0(outcome, "_rate_weighted")]] <- unname(vapply(flags, function(flag) {
      denominator <- summary[[paste0(flag, "_", outcome, "_weighted_n")]][[1L]]
      if (denominator == 0) NA_real_ else
        summary[[paste0(flag, "_", outcome, "_weighted_events")]][[1L]] / denominator
    }, numeric(1)))
  }
  result
}
