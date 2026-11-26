nis_reweight_data <- function(design, weights_quo, call) {
  rows <- nis_cohort_design_rows(design, call)
  variables <- rows$variables
  placeholders <- rows$placeholders

  weight_values <- rlang::eval_tidy(weights_quo, data = variables)
  if (!is.numeric(weight_values) || !is.null(dim(weight_values))) {
    cli::cli_abort("`weights` must be a numeric vector or numeric column.", call = call)
  }
  if (length(weight_values) != nrow(variables)) {
    cli::cli_abort("`weights` must have one value per cohort row in `design`.", call = call)
  }
  if (!all(is.finite(weight_values))) {
    cli::cli_abort("`weights` must contain only finite values.", call = call)
  }
  if (any(weight_values <= 0)) {
    cli::cli_abort("`weights` must be positive.", call = call)
  }

  variables <- nis_cohort_design_restore(design, call)
  aligned <- variables[rep(NA_integer_, nrow(placeholders)), , drop = FALSE]
  for (field in .nis_cohort_structure_fields) {
    aligned[[field]] <- placeholders[[field]]
  }
  variables$.nis_weight <- variables$.nis_weight * as.numeric(weight_values)
  # survey stores reciprocals of weights.
  represented <- 1 / (1 / variables$.nis_weight)
  if (any(!is.finite(represented) | represented <= 0)) {
    cli::cli_abort("The reweighted design must have finite weights greater than zero.", call = call)
  }
  list(combined = dplyr::bind_rows(variables, aligned), variables = variables)
}

#' Reweight a cohort survey design
#'
#' Multiplies cohort discharge survey weights by supplied propensity weights,
#' retains the placeholder rows for hospital-years without cohort discharges,
#' and rebuilds the nested survey design. This experimental method is intended
#' for analysts who have validated their weighting specification against a
#' full-data reference design.
#'
#' @param design A result of [nis_design()].
#'   Column selection, renaming, and mutation are supported when cohort rows
#'   are unchanged. Required internal design fields are restored from survey
#'   metadata; removed analysis columns are not restored.
#' @param weights Numeric weights aligned with the cohort rows of `design`, or
#'   an unquoted numeric column name in the design data. They are matched to
#'   rows by position, so take them from `design$variables` in that order (for
#'   example, fit the propensity model on `design$variables`) and do not
#'   reorder or subset the rows first.
#'
#' @section Weighted totals:
#' The result multiplies the discharge weights by `weights`, so
#' `survey_total()` and similar totals no longer estimate national discharge
#' counts. Use the result for ratios, means and model estimates, and report
#' national counts from the design before reweighting. Each call multiplies the
#' weights again, so call `nis_reweight()` once on the result of
#' [nis_design()]; calling it on an already reweighted design compounds the
#' weights.
#'
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @family survey-design
#' @seealso [Survey design and weighting](articles/survey-design.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE))
#'
#' # Illustrative weights only; use weights from your own validated model
#' reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
#' srvyr::summarise(reweighted, weighted_total = srvyr::survey_total())
nis_reweight <- function(design, weights) {
  call <- rlang::current_call()
  rows <- nis_reweight_data(design, rlang::enquo(weights), call)
  variables <- rows$variables
  combined <- rows$combined
  # bind_rows() drops variable labels; restore them before rebuilding the design.
  for (name in names(variables)) {
    label <- attr(variables[[name]], "label", exact = TRUE)
    if (!is.null(label)) attr(combined[[name]], "label") <- label
  }
  reweighted <- nis_cohort_design(combined, attr(design, "nis_excluded", exact = TRUE), nis_cost_provenance(design))
  nis_cohort_check_rebuild(design, reweighted, call)
  reweighted
}
