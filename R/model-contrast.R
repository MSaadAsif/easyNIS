#' Contrast experimental survey model coefficients with an explicit interpretation
#'
#' Computes a caller-declared linear contrast using the full fitted coefficient
#' covariance, including interactions. The caller must supply the difference
#' between the intended model-matrix profiles. This function does not construct
#' profiles or verify their scientific meaning. Intercept weights must be zero.
#'
#' @param model A [nis_model()] result.
#' @param contrast Nonempty plain named numeric vector of finite coefficient
#'   weights. Names must uniquely match fitted coefficients. Omitted weights
#'   are zero. All-zero contrasts and nonzero weights on aliases are refused.
#' @param interpretation Explicitly choose `"link_difference"`,
#'   `"mean_difference"`, `"odds_ratio"`, `"mean_ratio"` or `"rate_ratio"`.
#'   Link differences permit every supported model. Mean differences require
#'   a Gaussian named outcome. Odds ratios require quasibinomial; mean ratios
#'   require quasipoisson without an offset; rate ratios require quasipoisson
#'   with a log-exposure offset. Transformed Gaussian outcomes require the link
#'   label. Interpreted effects refuse nonconverged or boundary fits.
#' @return A `nis_model_contrast` list with `estimate`, `effect_se`, `lower`,
#'   `upper`, `link_estimate`, `link_se`, `link_variance`, `link_lower`,
#'   `link_upper`, `statistic` and `p_value`. Tests always use link null zero;
#'   the effect null is one for ratios and zero for differences. The original
#'   `model`, complete weights, interpretation, sample, factors, diagnostics,
#'   response/exposure `scales` and full provenance are retained. The model
#'   and its native fit are unchanged. Ratios exponentiate link Wald bounds;
#'   their effect SE uses the delta method. Zero variance is accepted, with an
#'   undefined statistic/p-value for a zero estimate divided by zero SE.
#' @details Caller-selected df and confidence are inherited from the model.
#'   Finite df uses t Wald inference; infinite df uses normal Wald inference.
#'   Rate contrasts compare expected outcome per exposure and exclude any
#'   difference in the fixed log-exposure term. Link contrasts also exclude that
#'   offset term. Ratios are conditional model contrasts, not risk ratios or
#'   causal effects. Annual support and scientific approval remain pending.
#' @seealso [nis_model()]
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$x <- rep(c(-2, -1, 1), 4L) + rep(c(-0.4, 0.2, 0.6, -0.3), each = 3L)
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), c("LOS", "x"),
#'     TRUE, "hospital_wr", "fail")
#'   fit <- nis_model(design, LOS ~ x, "gaussian", "fail",
#'     df = 2, confidence = 0.95, variance = "wr_unadjusted")
#'   result <- nis_model_contrast(fit, c(x = 2), "mean_difference")
#'   result$estimate
#'   nis_close(session)
#'   unlink(path)
#' }
nis_model_contrast <- function(model, contrast, interpretation) {
  if (!inherits(model, "nis_model") || !inherits(model$native, "svyglm")) {
    stop("`model` must be a nis_model result.", call. = FALSE)
  }
  if (missing(interpretation)) {
    stop("Choose an explicit contrast interpretation.", call. = FALSE)
  }
  check_string(interpretation, "interpretation")
  if (!interpretation %in% c("link_difference", "mean_difference", "odds_ratio", "mean_ratio", "rate_ratio")) {
    stop("Unsupported contrast interpretation.", call. = FALSE)
  }
  if (!is.numeric(contrast) || is.complex(contrast) || is.object(contrast) ||
      !is.null(dim(contrast)) || !length(contrast) || any(!is.finite(contrast)) ||
      is.null(names(contrast)) || anyNA(names(contrast)) || any(!nzchar(names(contrast))) ||
      anyDuplicated(names(contrast)) || !any(contrast != 0)) {
    stop("Supply nonempty finite plain named numeric contrast weights with unique nonempty names and a nonzero weight.",
         call. = FALSE)
  }
  coefficients <- stats::coef(model$native, na.rm = FALSE)
  if (!all(names(contrast) %in% names(coefficients))) {
    stop("Contrast names must match fitted coefficient names.", call. = FALSE)
  }
  weights <- stats::setNames(numeric(length(coefficients)), names(coefficients))
  weights[names(contrast)] <- contrast
  if ("(Intercept)" %in% names(weights) && weights[["(Intercept)"]] != 0) {
    stop("Profile differences require a zero intercept weight.", call. = FALSE)
  }
  if (any(weights[is.na(coefficients)] != 0)) {
    stop("Nonzero contrast weights on aliased coefficients are unsupported.", call. = FALSE)
  }
  family <- model$provenance$family
  has_offset <- !is.null(model$provenance$offset)
  permitted <- switch(interpretation,
    link_difference = TRUE,
    mean_difference = family == "gaussian" && model$provenance$modeled_scale == "named_outcome",
    odds_ratio = family == "quasibinomial",
    mean_ratio = family == "quasipoisson" && !has_offset,
    rate_ratio = family == "quasipoisson" && has_offset)
  if (!isTRUE(permitted)) {
    stop("Interpretation is incompatible with the model family, response scale or exposure offset.", call. = FALSE)
  }
  if (interpretation != "link_difference" &&
      (!isTRUE(model$diagnostics$converged) || isTRUE(model$diagnostics$boundary))) {
    stop("Interpreted effects require a converged nonboundary fit; use link_difference for inspection.", call. = FALSE)
  }
  # Remove zero weights before multiplication so zero aliases and extreme
  # inactive covariance entries cannot introduce NA or overflow.
  active <- names(weights)[weights != 0]
  covariance <- stats::vcov(model$native)[active, active, drop = FALSE]
  active_weights <- weights[active]
  link_estimate <- unname(sum(active_weights * coefficients[active]))
  link_variance <- unname(drop(crossprod(active_weights, covariance %*% active_weights)))
  if (!is.finite(link_estimate) || !is.finite(link_variance) || link_variance < 0) {
    stop("Contrast estimate and nonnegative variance must be finite.", call. = FALSE)
  }
  link_se <- sqrt(link_variance)
  df <- model$provenance$df
  confidence <- model$provenance$confidence
  critical <- if (is.infinite(df)) stats::qnorm((1 - confidence) / 2, lower.tail = FALSE) else
    stats::qt((1 - confidence) / 2, df, lower.tail = FALSE)
  margin <- if (link_se == 0) 0 else critical * link_se
  link_bounds <- c(link_estimate - margin, link_estimate + margin)
  if (any(!is.finite(c(link_se, link_bounds)))) {
    stop("Contrast SE and interval bounds must be finite.", call. = FALSE)
  }
  statistic <- link_estimate / link_se
  p_value <- if (is.infinite(df)) 2 * stats::pnorm(abs(statistic), lower.tail = FALSE) else
    2 * stats::pt(abs(statistic), df, lower.tail = FALSE)
  ratio <- interpretation %in% c("odds_ratio", "mean_ratio", "rate_ratio")
  estimate <- if (ratio) exp(link_estimate) else link_estimate
  bounds <- if (ratio) exp(link_bounds) else link_bounds
  effect_se <- if (ratio) estimate * link_se else link_se
  if (any(!is.finite(c(estimate, effect_se, bounds))) || (ratio && any(c(estimate, bounds) <= 0))) {
    stop("Effect estimate, SE and interval bounds must be finite; ratios must remain strictly positive.", call. = FALSE)
  }
  scales <- list(response_expression = model$provenance$response_expression,
    response_fields = model$provenance$response_fields,
    modeled_scale = model$provenance$modeled_scale, link = model$provenance$link,
    effect = interpretation, exposure = model$provenance$offset,
    offset_difference_included = FALSE)
  structure(list(estimate = estimate, effect_se = effect_se, lower = bounds[1L], upper = bounds[2L],
    link_estimate = link_estimate, link_se = link_se, link_variance = link_variance,
    link_lower = link_bounds[1L], link_upper = link_bounds[2L], statistic = statistic, p_value = p_value,
    null = if (ratio) 1 else 0, test_null = 0, test_scale = "link", df = df, confidence = confidence,
    contrast = weights, interpretation = interpretation, model = model,
    sample = model$sample, factors = model$factors, diagnostics = model$diagnostics, scales = scales,
    provenance = list(model = model$provenance, supplied_contrast = contrast,
      contrast = weights, interpretation = interpretation, scales = scales,
      variance = "full_coefficient_covariance", df = df, confidence = confidence,
      interval = model$provenance$interval, test_scale = "link", test_null = 0,
      effect_se_method = if (ratio) "delta" else "linear",
      scope = "experimental_model_contrast", analysis_ready = FALSE)), class = "nis_model_contrast")
}
