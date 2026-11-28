#' Report the survey design and fitted sample
#'
#' Report the discharges and survey weights used in a design or fitted model.
#'
#' @details Use the report to reconcile input, cohort, and analysis counts.
#' After filtering a design, the current domain count changes while the
#' original sample count is retained. Review disclosure before sharing
#' the report.
#'
#' @param x A [nis_design()] result, including a filtered or reweighted design,
#'   or a [survey::svyglm()] fit made with that design.
#'
#' @return A `nis_design_report` list with the valid-design input years,
#'   input and original cohort counts, design-field exclusions,
#'   cohort criterion, and current domain count. Weighting fields describe the
#'   base weight column, annualization divisor, and whether supplied reweights
#'   were applied. The PSU and stratum fields name their year-scoped keys.
#'   For a fit, `domain_n` counts the records after any model subset and before
#'   the fit's missing-data action. The `model` entry gives the fitted
#'   unweighted count (`n`, from [stats::nobs()]) and the number of records
#'   the fit omitted for missing model data (`excluded_n`). The print method
#'   summarizes sample stages and weighting. Use `$` to access details
#'   such as `excluded`.
#'
#' @family survey-design
#' @seealso [Analyze your first NIS cohort](https://msaadasif.github.io/easyNIS/articles/getting-started.html)
#' @export
#' @examples
#' data <- nis_open(nis_example(2019:2020))
#' design <- nis_design(data, AGE >= 18, keep = c(AGE, LOS), annualize = TRUE)
#' nis_design_report(survey::svyglm(LOS ~ AGE, design = design))
nis_design_report <- function(x) {
  is_fit <- inherits(x, "svyglm")
  design <- if (is_fit) x$survey.design else x
  input <- attr(design, "nis_design_input", exact = TRUE)
  if (is.null(input)) {
    cli::cli_abort("`x` must be a `nis_design()` result or a `survey::svyglm()` fit from one.")
  }
  omitted <- if (is_fit) length(x$na.action) else 0L
  report <- list(
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
  structure(report, class = c("nis_design_report", "list"))
}

#' @export
print.nis_design_report <- function(x, ...) {
  stages <- c("Input sample", "Original cohort", "Current domain")
  counts <- c(x$input_n, x$cohort_n, x$domain_n)
  if (!is.null(x$model)) {
    stages <- c(stages, "Fitted model")
    counts <- c(counts, x$model$n)
  }

  weight <- x$weight
  if (x$annualize) {
    weight <- paste(weight, "/", x$divisor)
  }
  if (x$reweighted) {
    weight <- paste(weight, "(reweighted)")
  }
  cat("NIS design report\n")
  cat("Years: ", paste(x$years, collapse = ", "), "\n", sep = "")
  cat("Weights: ", weight, "\n", sep = "")
  print(dplyr::tibble(stage = stages, discharges = counts), ...)
  invisible(x)
}
