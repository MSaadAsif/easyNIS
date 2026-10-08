#' Fit an experimental survey regression with explicit accounting
#'
#' Fits a native survey GLM on a complete-case domain without rebuilding the
#' original hospital design. This first increment supports named outcomes and
#' ordinary terms, row-wise numeric transformations and Poisson log-exposure
#' offsets. Dot expansion, grouped responses and custom families are refused.
#' Inference remains experimental and does not approve annual support.
#'
#' @param design A [nis_survey_design()], [nis_pool_design()] or [nis_domain()]
#'   result using hospital WR variance and singleton rejection.
#' @param formula Two-sided R formula with retained named fields and ordinary
#'   terms/interactions. Gaussian outcomes and predictors may use row-wise
#'   arithmetic, `log`, `log1p`, `sqrt`, `abs` and `I`. Quasi-family outcomes
#'   remain named vectors. Quasipoisson permits one `offset(log(exposure))`
#'   with a named positive numeric exposure field. Global variables, caller
#'   functions, sample-dependent transforms and `.` expansion are refused.
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
#'   Converged nonboundary quasi-family fits restart once from their fitted
#'   coefficients to refine final IRLS working weights at the same tolerance.
#'   Initial/final iteration counts and restart status are retained.
#'   Native offset predictions are unsupported: `predict.svyglm` may omit the
#'   exposure offset. Offset fits retain this limitation in diagnostics.
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
  if (!inherits(formula, "formula") || length(formula) != 3L ||
      !model_expression_supported(formula[[2L]]) || !length(all.vars(formula[[2L]]))) {
    stop("Supply a two-sided formula with a named or supported transformed outcome.", call. = FALSE)
  }
  if (family != "gaussian" && !is.symbol(formula[[2L]])) {
    stop("Quasi-family outcomes must remain named vectors; transformed outcomes are Gaussian only.", call. = FALSE)
  }
  if (!model_terms_supported(formula[[3L]])) {
    stop("Use supported row-wise terms; arbitrary functions and dot expansion are unsupported.",
         call. = FALSE)
  }
  fields <- all.vars(formula)
  response_fields <- all.vars(formula[[2L]])
  exposures <- model_offset_fields(formula[[3L]])
  if (length(exposures) > 1L || (length(exposures) && family != "quasipoisson")) {
    stop("Only one log-exposure offset in a quasipoisson model is supported.", call. = FALSE)
  }
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
  if (any(vapply(rows[response_fields], is.factor, logical(1)))) {
    stop("Model outcome source fields must be numeric or logical.", call. = FALSE)
  }
  outcome <- if (is.symbol(formula[[2L]])) rows[[as.character(formula[[2L]])]] else NULL
  if (family == "quasibinomial" && any(!outcome[!is.na(outcome)] %in% c(0, 1))) {
    stop("Logistic outcomes must be observed zero/one values.", call. = FALSE)
  }
  if (family == "quasipoisson" && any(outcome < 0, na.rm = TRUE)) {
    stop("Poisson-family outcomes must be nonnegative.", call. = FALSE)
  }
  for (field in exposures) {
    exposure <- rows[[field]]
    if (!is.numeric(exposure) || any(exposure <= 0, na.rm = TRUE)) {
      stop("Exposure must be numeric with strictly positive observed values.", call. = FALSE)
    }
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
  # Allowed transforms are row-wise and resolve independently of caller functions.
  fit_formula <- as.call(list(as.name("~"), formula[[2L]], formula[[3L]]))
  class(fit_formula) <- "formula"
  environment(fit_formula) <- list2env(list(offset = stats::offset), parent = baseenv())
  warnings <- character()
  capture_warning <- function(w) {
    warnings <<- unique(c(warnings, conditionMessage(w)))
    invokeRestart("muffleWarning")
  }
  full_frame <- withCallingHandlers(stats::model.frame(fit_formula, rows,
    na.action = stats::na.pass, drop.unused.levels = TRUE), warning = capture_warning)
  validate_model_frame(full_frame, rows)
  frame <- if (all(keep)) full_frame else withCallingHandlers(stats::model.frame(
    fit_formula, analysis$variables, na.action = stats::na.fail, drop.unused.levels = TRUE),
    warning = capture_warning)
  predictor_fields <- names(frame)[-1L]
  factor_fields <- predictor_fields[vapply(frame[predictor_fields], function(x) {
    is.factor(x) || is.logical(x)
  }, logical(1))]
  for (field in factor_fields) {
    if (is.logical(frame[[field]])) frame[[field]] <- factor(frame[[field]], levels = c(FALSE, TRUE))
  }
  contrasts <- withCallingHandlers(lapply(frame[factor_fields], stats::contrasts), warning = capture_warning)
  native_family <- switch(family, gaussian = stats::gaussian(),
    quasibinomial = stats::quasibinomial(), quasipoisson = stats::quasipoisson())
  fit_arguments <- list(formula = fit_formula, design = analysis,
    family = native_family, na.action = stats::na.fail, rescale = TRUE,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
  if (length(contrasts)) fit_arguments$contrasts <- contrasts
  native <- withCallingHandlers(do.call(survey::svyglm, fit_arguments), warning = capture_warning)
  initial_iterations <- native$iter
  refined <- family != "gaussian" && isTRUE(native$converged) && !isTRUE(native$boundary)
  if (refined) {
    start <- stats::coef(native, na.rm = FALSE)
    start[is.na(start)] <- 0
    fit_arguments$start <- unname(start)
    native <- withCallingHandlers(do.call(survey::svyglm, fit_arguments), warning = capture_warning)
  }
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
    diagnostics = list(warnings = warnings, converged = native$converged, iterations = native$iter,
      initial_iterations = initial_iterations, refined = refined,
      native_offset_prediction = if (length(exposures)) "unsupported" else "not_applicable",
      rank = native$rank, aliased = names(estimates)[!estimable],
      boundary = native$boundary),
    provenance = list(formula = paste(deparse(formula), collapse = " "), fields = fields,
      family = family, link = native_family$link,
      modeled_scale = if (is.symbol(formula[[2L]])) "named_outcome" else "transformed_outcome",
      response_expression = paste(deparse(formula[[2L]]), collapse = " "),
      response_fields = response_fields,
      offset = if (length(exposures)) list(field = exposures,
        expression = paste(deparse(call("log", as.name(exposures))), collapse = " "), coefficient = 1) else NULL,
      coefficient_scale = "link", missing = missing, df = as.double(df),
      confidence = as.double(confidence), variance = variance,
      interval = if (is.infinite(df)) "normal_wald" else "t_wald",
      fitting_weight_rescale = "sum_to_analysis_rows", survey_version = as.character(utils::packageVersion("survey")),
      fitting_control = list(epsilon = 1e-10, maxit = 50L),
      fitting_refinement = "one_converged_nonboundary_quasi_restart",
      current_survey_options = options()[grepl("^survey[.]", names(options()))],
      design = design$provenance, population = design$population, domains = design$domains,
      scope = "experimental_survey_glm", analysis_ready = FALSE)), class = "nis_model")
}

model_terms_supported <- function(term) {
  if (is.symbol(term)) return(as.character(term) != ".")
  if (is.numeric(term)) return(length(term) == 1L && is.finite(term))
  if (!is.call(term) || !is.symbol(term[[1L]])) return(FALSE)
  operation <- as.character(term[[1L]])
  if (operation == "offset") {
    return(length(term) == 2L && is.call(term[[2L]]) && length(term[[2L]]) == 2L &&
      identical(term[[2L]][[1L]], as.name("log")) && is.symbol(term[[2L]][[2L]]) &&
      as.character(term[[2L]][[2L]]) != ".")
  }
  if (operation %in% c("log", "log1p", "sqrt", "abs", "I")) return(model_expression_supported(term))
  if (!operation %in% c("+", "-", "*", ":", "/", "^", "(")) return(FALSE)
  all(vapply(as.list(term)[-1L], model_terms_supported, logical(1)))
}

model_expression_supported <- function(expression) {
  if (is.symbol(expression)) return(as.character(expression) != ".")
  if (is.numeric(expression)) return(length(expression) == 1L && is.finite(expression))
  if (!is.call(expression) || !is.symbol(expression[[1L]])) return(FALSE)
  operation <- as.character(expression[[1L]])
  if (operation %in% c("log", "log1p", "sqrt", "abs", "I", "(")) {
    return(length(expression) == 2L && model_expression_supported(expression[[2L]]))
  }
  if (!operation %in% c("+", "-", "*", "/", "^") || !length(expression) %in% c(2L, 3L)) return(FALSE)
  all(vapply(as.list(expression)[-1L], model_expression_supported, logical(1)))
}

model_offset_fields <- function(expression) {
  if (!is.call(expression)) return(character())
  if (identical(expression[[1L]], as.name("offset"))) {
    return(as.character(expression[[2L]][[2L]]))
  }
  unlist(lapply(as.list(expression)[-1L], model_offset_fields), use.names = FALSE)
}

validate_model_frame <- function(frame, rows) {
  expressions <- as.list(attr(attr(frame, "terms"), "variables"))[-1L]
  for (i in seq_along(frame)) {
    value <- frame[[i]]
    if (!is.null(dim(value)) || (!is.factor(value) && !is.numeric(value) && !is.logical(value))) {
      stop("Transformed model terms must be single numeric/logical vectors or factors.", call. = FALSE)
    }
    if (!is.factor(value) && any(is.infinite(value))) {
      stop("Nonfinite transformed model terms are unsupported.", call. = FALSE)
    }
    source_fields <- all.vars(expressions[[i]])
    observed_inputs <- if (length(source_fields)) stats::complete.cases(rows[source_fields]) else rep(TRUE, nrow(rows))
    if (any(is.na(value) & observed_inputs)) {
      stop("Transformed model terms produced missing values from observed inputs.", call. = FALSE)
    }
  }
}
