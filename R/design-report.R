#' Report the design and fitted sample for NIS analyses
#'
#' Reads the sampling metadata retained by [nis_design()] without querying the
#' original data. Use it on the design after a domain filter, or on a
#' [survey::svyglm()] fit from that design to see the fitted sample size.
#'
#' @param x A [nis_design()] result, including a filtered or reweighted design,
#'   or a [survey::svyglm()] fit made with that design.
#'
#' @return A list with the valid-design input years, input and original cohort
#'   counts, design-field exclusions (a discharge can fail multiple fields),
#'   cohort criterion, and current domain count. Weighting fields describe the
#'   base weight column, annualization divisor, and whether supplied reweights
#'   were applied. The PSU and stratum fields name their year-scoped keys.
#'   For a fit, `domain_n` counts the records after any model subset and before
#'   the fit's missing-data action. The `model` entry gives the fitted
#'   unweighted count (`n`, from [stats::nobs()]) and the number of records
#'   the fit omitted for missing model data (`excluded_n`).
#'
#' @details
#' Counts describe the input supplied to [nis_design()]. Filtering that input
#' before making the design can change the sampling roster. Use a cohort
#' expression or filter the design to restrict a survey domain.
#' Review the counts for disclosure before sharing them.
#' @family survey-design
#' @export
#' @examples
#' data <- nis_open(nis_example(2019:2020))
#' design <- nis_design(data, AGE >= 18, keep = c(AGE, LOS), annualize = TRUE)
#' nis_design_report(design)
#' nis_design_report(survey::svyglm(LOS ~ AGE, design = design))
nis_design_report <- function(x) {
  is_fit <- inherits(x, "svyglm")
  design <- if (is_fit) x$survey.design else x
  input <- attr(design, "nis_design_input", exact = TRUE)
  if (is.null(input)) {
    cli::cli_abort("`x` must be a `nis_design()` result or a `survey::svyglm()` fit from one.")
  }
  omitted <- if (is_fit) length(x$na.action) else 0L
  list(
    years = input$years,
    cohort = input$cohort,
    input_n = input$rows,
    excluded = attr(design, "nis_excluded", exact = TRUE),
    cohort_n = attr(design, "nis_cohort_rows", exact = TRUE),
    domain_n = nrow(design$variables) + omitted,
    weight = "DISCWT",
    psu = c("YEAR", "HOSP_NIS"),
    strata = c("YEAR", "NIS_STRATUM"),
    nest = TRUE,
    annualize = input$annualize,
    divisor = input$divisor,
    reweighted = input$reweighted,
    model = if (is_fit) list(n = stats::nobs(x), excluded_n = omitted)
  )
}
