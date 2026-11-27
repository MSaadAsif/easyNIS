nis_reweight_data <- function(design, weights_quo, call) {
  rows <- nis_cohort_design_rows(design, call)
  variables <- rows$variables
  placeholders <- rows$placeholders[.nis_cohort_structure_fields]

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

  structure <- nis_cohort_design_restore(design, call)
  structure$.nis_weight <- structure$.nis_weight * as.numeric(weight_values)
  # survey stores reciprocals of weights.
  represented <- 1 / (1 / structure$.nis_weight)
  if (any(!is.finite(represented) | represented <= 0)) {
    cli::cli_abort("The reweighted design must have finite weights greater than zero.", call = call)
  }
  list(
    structure = dplyr::bind_rows(structure, placeholders),
    placeholders = placeholders,
    variables = variables[setdiff(names(variables), c(.nis_cohort_structure_fields, ".in_cohort"))]
  )
}

#' Reweight a cohort survey design
#'
#' Multiply the cohort's discharge weights by prespecified analysis factors.
#'
#' @details The design retains the original hospital and stratum structure.
#' Uncertainty estimates treat the supplied factors as fixed.
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
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @family survey-design
#' @seealso [Make tables and fit survey models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html),
#'   [Make tables and fit survey models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(2019:2020))
#' design <- nis_design(nis, AGE >= 18, keep = c(AGE, LOS))
#' reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
#' srvyr::summarise(reweighted, mean_los = srvyr::survey_mean(LOS))
nis_reweight <- function(design, weights) {
  call <- rlang::current_call()
  rows <- nis_reweight_data(design, rlang::enquo(weights), call)
  reweighted <- nis_cohort_design(
    rows$variables,
    rows$structure,
    rows$placeholders,
    attr(design, "nis_excluded", exact = TRUE),
    nis_cost_provenance(design)
  )
  nis_cohort_check_rebuild(design, reweighted, call)
  input <- attr(design, "nis_design_input", exact = TRUE)
  if (!is.null(input)) {
    input$reweighted <- TRUE
    attr(reweighted, "nis_design_input") <- input
  }
  reweighted
}
