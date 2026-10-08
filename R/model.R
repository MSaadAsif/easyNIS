#' Fit an experimental survey regression with explicit accounting
#'
#' Fits a native survey GLM on a complete-case domain without rebuilding the
#' original hospital design. This first increment supports named outcomes and
#' ordinary formula terms and interactions. Transformations, offsets, dot
#' expansion, grouped responses and custom families require later contracts.
#' Inference remains experimental and does not approve annual support.
#'
#' @param design A [nis_survey_design()], [nis_pool_design()] or [nis_domain()]
#'   result using hospital WR variance and singleton rejection.
#' @param formula Two-sided R formula with one named outcome, retained named
#'   predictors, and ordinary `+`, `-`, `*`, `:`, `/`, `^` terms. Precompute
#'   transformations explicitly before design construction. Global variables
#'   and `.` expansion are refused.
#' @param family Explicitly choose `"gaussian"` for identity-link means,
#'   `"quasibinomial"` for logit-link zero/one outcomes or `"quasipoisson"`
#'   for log-link nonnegative outcomes. No effect exponentiation is performed.
#' @param missing Explicitly choose `"fail"` or complete-case `"exclude"`.
#'   NA and NaN are missing. Infinite values are refused. Raw sentinels remain.
#' @param df Explicit positive numeric scalar or `Inf` for coefficient Wald
#'   tests and intervals. Native residual and design df are reported separately.
#' @param confidence Explicit confidence level strictly between zero and one.
#' @param variance Must explicitly be `"wr_unadjusted"`. Current survey options
#'   must specify lonely PSU `"fail"` and domain adjustment `FALSE`.
#' @return A `nis_model` list with the unchanged native `svyglm` in `native`,
#'   its explicit-df `summary`, link-scale numeric `coefficients`, analysis
#'   `design`, `sample` accounting, factor contrast matrices in `factors`,
#'   `diagnostics` including captured warnings, and full `provenance`.
#'   Aliased coefficients have NA inference. Nonconvergence is recorded, not
#'   concealed. Raw design columns and caller options are unchanged. Native
#'   fitting rescales weights to sum to analysis rows for numerical stability;
#'   analysis design weights retain their original pooling divisor.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), "LOS",
#'     TRUE, "hospital_wr", "fail")
#'   result <- nis_model(design, LOS ~ 1, "gaussian", "exclude",
#'     df = 2, confidence = 0.95, variance = "wr_unadjusted")
#'   result$coefficients
#'   nis_close(session)
#'   unlink(path)
#' }
nis_model <- function(design, formula, family, missing, df, confidence, variance) {
  if (!inherits(design, "nis_survey") ||
      !identical(design$provenance$method, "hospital_wr") ||
      !identical(design$provenance$singleton, "fail")) {
    stop("`design` must be an experimental hospital WR nis_survey result.", call. = FALSE)
  }
  if (base::missing(family) || base::missing(missing) || base::missing(df) ||
      base::missing(confidence) || base::missing(variance)) {
    stop("Choose explicit family, missing, df, confidence and variance policies.", call. = FALSE)
  }
  check_string(family, "family")
  check_string(missing, "missing")
  check_string(variance, "variance")
  if (!family %in% c("gaussian", "quasibinomial", "quasipoisson") ||
      !missing %in% c("fail", "exclude") || variance != "wr_unadjusted") {
    stop("Unsupported family, missing or variance policy.", call. = FALSE)
  }
  if (!is.numeric(df) || is.complex(df) || is.object(df) || length(df) != 1L || is.na(df) || df <= 0 ||
      !is.numeric(confidence) || is.complex(confidence) || is.object(confidence) ||
      length(confidence) != 1L || is.na(confidence) || confidence <= 0 || confidence >= 1) {
    stop("Supply positive numeric df or Inf and numeric confidence between zero and one.", call. = FALSE)
  }
  if (!identical(getOption("survey.lonely.psu"), "fail") ||
      !identical(getOption("survey.adjust.domain.lonely"), FALSE)) {
    stop("wr_unadjusted requires survey.lonely.psu = \"fail\" and survey.adjust.domain.lonely = FALSE.",
         call. = FALSE)
  }
  if (!inherits(formula, "formula") || length(formula) != 3L || !is.symbol(formula[[2L]])) {
    stop("Supply a two-sided formula with one named outcome.", call. = FALSE)
  }
  if (!model_terms_supported(formula[[3L]])) {
    stop("Use named predictors and ordinary terms; transformations, offsets and dot expansion are unsupported.",
         call. = FALSE)
  }
  fields <- all.vars(formula)
  if (any(fields %in% c(".survey.prob.weights", "(weights)", "(offset)"))) {
    stop("Native reserved weight/offset field names cannot be modeled.", call. = FALSE)
  }
  rows <- design$design$variables
  if (!all(fields %in% names(rows))) {
    stop("Every formula field must be retained in the design; global variables are unsupported.", call. = FALSE)
  }
  for (field in fields) {
    x <- rows[[field]]
    if (!is.null(dim(x)) || (!is.factor(x) &&
        ((!is.numeric(x) && !is.logical(x)) || is.object(x) || is.complex(x)))) {
      stop("Model fields must be plain numeric/logical vectors or explicit factors; BIGINT requires conversion.",
           call. = FALSE)
    }
    if (!is.factor(x) && any(is.infinite(x))) {
      stop("Infinite model values are unsupported.", call. = FALSE)
    }
  }
  outcome <- rows[[as.character(formula[[2L]])]]
  if (is.factor(outcome)) stop("Model outcomes must be numeric or logical.", call. = FALSE)
  if (family == "quasibinomial" && any(!outcome[!is.na(outcome)] %in% c(0, 1))) {
    stop("Logistic outcomes must be observed zero/one values.", call. = FALSE)
  }
  if (family == "quasipoisson" && any(outcome < 0, na.rm = TRUE)) {
    stop("Poisson-family outcomes must be nonnegative.", call. = FALSE)
  }
  missing_fields <- vapply(rows[fields], function(x) sum(is.na(x)), numeric(1))
  keep <- stats::complete.cases(rows[fields])
  if (missing == "fail" && any(!keep)) stop("Model fields contain missing values.", call. = FALSE)
  if (!any(keep)) stop("Cannot fit an empty analysis.", call. = FALSE)
  analysis <- if (all(keep)) design$design else design$design[keep, ]
  denominator <- sum(stats::weights(analysis))
  if (!is.finite(denominator) || denominator <= 0) {
    stop("Analysis weight denominator must remain finite and positive.", call. = FALSE)
  }
  # A data-only environment prevents formula fallback to caller objects.
  fit_formula <- formula
  environment(fit_formula) <- baseenv()
  frame <- stats::model.frame(fit_formula, analysis$variables, na.action = stats::na.fail,
                              drop.unused.levels = TRUE)
  factor_fields <- names(frame)[vapply(frame, is.factor, logical(1))]
  contrasts <- lapply(frame[factor_fields], stats::contrasts)
  warnings <- character()
  capture_warning <- function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
  native_family <- switch(family, gaussian = stats::gaussian(),
    quasibinomial = stats::quasibinomial(), quasipoisson = stats::quasipoisson())
  fit_arguments <- list(formula = fit_formula, design = analysis,
    family = native_family, na.action = stats::na.fail, rescale = TRUE,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
  if (length(contrasts)) fit_arguments$contrasts <- contrasts
  native <- withCallingHandlers(do.call(survey::svyglm, fit_arguments), warning = capture_warning)
  summary <- withCallingHandlers(summary(native, df.resid = df), warning = capture_warning)
  estimates <- stats::coef(native, na.rm = FALSE)
  estimable <- !is.na(estimates)
  covariance <- stats::vcov(native)
  if (!any(estimable) || any(!is.finite(estimates[estimable])) ||
      any(!is.finite(covariance)) || any(diag(covariance) < 0)) {
    stop("Native fit did not return finite estimable coefficients and covariance.", call. = FALSE)
  }
  coefficients <- data.frame(term = names(estimates), estimate = unname(estimates),
    se = NA_real_, statistic = NA_real_, p_value = NA_real_, lower = NA_real_, upper = NA_real_,
    aliased = !estimable, stringsAsFactors = FALSE)
  at <- match(rownames(summary$coefficients), coefficients$term)
  coefficients[at, c("se", "statistic", "p_value")] <- summary$coefficients[, 2:4, drop = FALSE]
  critical <- if (is.infinite(df)) stats::qnorm((1 - confidence) / 2, lower.tail = FALSE) else
    stats::qt((1 - confidence) / 2, df, lower.tail = FALSE)
  margin <- ifelse(coefficients$se == 0, 0, critical * coefficients$se)
  coefficients$lower <- coefficients$estimate - margin
  coefficients$upper <- coefficients$estimate + margin
  if (any(!is.finite(coefficients$lower[estimable])) || any(!is.finite(coefficients$upper[estimable]))) {
    stop("Coefficient interval bounds are nonfinite.", call. = FALSE)
  }
  factors <- lapply(factor_fields, function(field) {
    matrix <- contrasts[[field]]
    list(levels = levels(frame[[field]]), ordered = is.ordered(frame[[field]]),
      contrasts = matrix, zero_coded_levels = rownames(matrix)[rowSums(abs(matrix)) == 0])
  })
  names(factors) <- factor_fields
  structure(list(native = native, summary = summary, coefficients = coefficients,
    design = analysis, factors = factors,
    sample = list(supplied = nrow(rows), included = sum(keep), excluded_missing = sum(!keep),
      missing_by_field = missing_fields, weighted_denominator = denominator,
      domain_degrees_of_freedom = survey::degf(design$design),
      analysis_degrees_of_freedom = survey::degf(analysis),
      full_population_degrees_of_freedom = design$population$degrees_of_freedom,
      native_residual_degrees_of_freedom = native$df.residual),
    diagnostics = list(warnings = warnings, converged = native$converged,
      rank = native$rank, aliased = names(estimates)[!estimable],
      boundary = native$boundary),
    provenance = list(formula = paste(deparse(formula), collapse = " "), fields = fields,
      family = family, link = native_family$link, modeled_scale = "named_outcome",
      coefficient_scale = "link", missing = missing, df = as.double(df),
      confidence = as.double(confidence), variance = variance,
      interval = if (is.infinite(df)) "normal_wald" else "t_wald",
      fitting_weight_rescale = "sum_to_analysis_rows", survey_version = as.character(utils::packageVersion("survey")),
      fitting_control = list(epsilon = 1e-10, maxit = 50L),
      current_survey_options = options()[grepl("^survey[.]", names(options()))],
      design = design$provenance, population = design$population, domains = design$domains,
      scope = "experimental_survey_glm", analysis_ready = FALSE)), class = "nis_model")
}

model_terms_supported <- function(term) {
  if (is.symbol(term)) return(as.character(term) != ".")
  if (is.numeric(term)) return(length(term) == 1L && is.finite(term))
  if (!is.call(term) || !is.symbol(term[[1L]]) ||
      !as.character(term[[1L]]) %in% c("+", "-", "*", ":", "/", "^", "(")) return(FALSE)
  all(vapply(as.list(term)[-1L], model_terms_supported, logical(1)))
}
