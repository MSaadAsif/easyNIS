#' Fit several experimental outcome models with shared predictors
#'
#' Declare each named outcome's family once and reuse a one-sided predictor
#' formula. Each outcome delegates to [nis_model()] on the supplied design,
#' retaining its own complete-case sample, native fit, warnings and provenance.
#' Inference is pointwise; no multiplicity correction or publication approval
#' is performed. A failed model rejects the batch without partial results.
#'
#' @param design An experimental [nis_survey_design()], [nis_pool_design()] or
#'   [nis_domain()] result accepted by [nis_model()].
#' @param outcomes A nonempty plain named character vector mapping unique exact
#'   outcome field names to `"gaussian"`, `"quasibinomial"` or `"quasipoisson"`.
#'   Outcomes are named fields; use [nis_model()] for transformed responses.
#' @param predictors A one-sided formula such as `~ exposure + age` or `~ 1`.
#'   Terms follow [nis_model()]'s existing restrictions. Field names are never
#'   parsed as code. Supplied formula environments and terms metadata are ignored.
#' @param missing Explicit `"fail"` or `"exclude"`, applied separately to the
#'   fields required by each model. Analyses can have different complete cases.
#' @param df Explicit positive numeric scalar or `Inf` for pointwise inference.
#' @param confidence Explicit confidence level strictly between zero and one.
#' @param variance Explicit `"wr_unadjusted"`; existing model option guards apply.
#' @return A `nis_models` list with `models` named by outcome, numeric sample
#'   accounting in `sample`, and shared declarations in `provenance`.
#'   Each `models` entry is a complete `nis_model` result. Sample rows report
#'   `outcome`, `family`, `raw_supplied`, `raw_included`, `raw_missing` and
#'   `weighted_denominator`. Counts overlap across models and must not be summed
#'   as distinct discharges. Results are unreviewed and `analysis_ready` is FALSE.
#'   Errors from a model have class `nis_models_error`, identify the `outcome`
#'   and retain the original error in `parent`; no partial batch is returned.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$adult <- core$AGE >= 18
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), c("LOS", "adult"),
#'     TRUE, "hospital_wr", "fail")
#'   batch <- nis_models(design, c(LOS = "gaussian", adult = "quasibinomial"),
#'     ~ 1, "exclude", 2, 0.95, "wr_unadjusted")
#'   batch$sample
#'   batch$models$LOS$coefficients
#'   nis_close(session)
#'   unlink(path)
#' }
nis_models <- function(design, outcomes, predictors, missing, df, confidence, variance) {
  if (base::missing(missing) || base::missing(df) || base::missing(confidence) ||
      base::missing(variance)) {
    stop("Choose explicit missing, df, confidence and variance policies.", call. = FALSE)
  }
  fields <- names(outcomes)
  if (!is.character(outcomes) || is.object(outcomes) || !is.null(dim(outcomes)) ||
      !length(outcomes) || is.null(fields) || anyNA(outcomes) || anyNA(fields) ||
      any(!nzchar(trimws(fields))) || anyDuplicated(fields) ||
      any(!outcomes %in% c("gaussian", "quasibinomial", "quasipoisson"))) {
    stop("`outcomes` must map unique nonempty field names to explicit supported families in a plain named character vector.",
         call. = FALSE)
  }
  if (!inherits(predictors, "formula") || length(predictors) != 2L) {
    stop("`predictors` must be a one-sided formula, for example ~ age + exposure.", call. = FALSE)
  }
  models <- lapply(seq_along(outcomes), function(i) {
    # Build language objects directly: punctuation in a field is literal.
    formula <- stats::as.formula(call("~", as.name(fields[i]), predictors[[2L]]),
                                env = baseenv())
    tryCatch(nis_model(design, formula, outcomes[[i]], missing, df, confidence, variance),
      error = function(error) {
        stop(structure(list(message = paste0("Model for outcome '", fields[i], "' failed: ",
          conditionMessage(error)), call = NULL, outcome = fields[i], parent = error),
          class = c("nis_models_error", "error", "condition")))
      })
  })
  names(models) <- fields
  sample <- data.frame(outcome = fields, family = unname(outcomes),
    raw_supplied = vapply(models, function(model) as.double(model$sample$supplied), numeric(1)),
    raw_included = vapply(models, function(model) as.double(model$sample$included), numeric(1)),
    raw_missing = vapply(models, function(model) as.double(model$sample$excluded_missing), numeric(1)),
    weighted_denominator = vapply(models, function(model) model$sample$weighted_denominator, numeric(1)),
    row.names = NULL, stringsAsFactors = FALSE)
  provenance <- list(outcomes = outcomes,
    predictors = paste(deparse(predictors[[2L]], width.cutoff = 500L), collapse = " "),
    missing = missing, df = df, confidence = confidence, variance = variance,
    interval_scope = "pointwise", multiplicity_adjustment = "none",
    disclosure_status = "unreviewed", analysis_ready = FALSE)
  structure(list(models = models, sample = sample, provenance = provenance), class = "nis_models")
}
