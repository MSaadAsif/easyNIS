nis_study_model_input_status <- function(data, outcome, exposure) {
  if (!is.data.frame(data)) {
    return("The model data are unavailable.")
  }
  if (nrow(data) == 0L) {
    return("The cohort has no rows after applying the study design.")
  }
  required <- c(outcome, exposure)
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    return(paste("The model data are missing", paste(missing, collapse = ", "), "."))
  }
  NULL
}

nis_study_formula_status <- function(data, formula) {
  model_frame <- tryCatch(
    stats::model.frame(formula, data = data, na.action = stats::na.omit, drop.unused.levels = TRUE),
    error = function(error) error
  )
  if (inherits(model_frame, "error")) {
    return(list(
      status = paste(
        "The declared model specification fails on complete-case rows:",
        conditionMessage(model_frame),
        "Review covariate levels and missingness; no terms were removed."
      )
    ))
  }
  if (nrow(model_frame) == 0L) {
    return(list(status = "The declared model has no complete-case rows after applying its covariates."))
  }
  outcome_values <- stats::model.response(model_frame)
  status <- nis_study_matrix_status(formula, model_frame)
  if (!is.null(status)) {
    return(status)
  }
  list(status = NULL, model_frame = model_frame, outcome_values = outcome_values)
}

nis_study_matrix_status <- function(formula, model_frame) {
  model_matrix <- tryCatch(stats::model.matrix(formula, data = model_frame), error = function(error) error)
  if (inherits(model_matrix, "error")) {
    return(list(
      status = paste(
        "The declared model specification fails on complete-case rows:",
        conditionMessage(model_matrix),
        "Review covariate levels and missingness; no terms were removed."
      )
    ))
  }
  if (!all(is.finite(model_matrix))) {
    return(list(
      status = paste(
        "The declared model matrix contains non-finite values on complete-case rows.",
        "Review numeric covariates for Inf or NaN; no terms were removed."
      )
    ))
  }
  matrix_rank <- tryCatch(qr(model_matrix)$rank, error = function(error) error)
  if (inherits(matrix_rank, "error")) {
    return(list(
      status = paste(
        "The declared model matrix rank could not be evaluated on complete-case rows:",
        conditionMessage(matrix_rank),
        "Review covariate values and collinearity; no terms were removed."
      )
    ))
  }
  if (matrix_rank < ncol(model_matrix)) {
    return(list(
      status = paste(
        "The declared model matrix is rank-deficient on complete-case rows.",
        "Review covariate variation, missingness, and collinearity; no terms were removed."
      )
    ))
  }
  NULL
}

nis_study_variable_status <- function(model_frame, outcome_values, outcome, exposure, suffix) {
  exposure_values <- model_frame[[exposure]]
  exposure_values <- exposure_values[!is.na(exposure_values)]
  if (is.numeric(exposure_values) && !all(is.finite(exposure_values))) {
    return(paste0("The exposure ", exposure, " contains non-finite values", suffix))
  }
  if (length(unique(exposure_values)) < 2L) {
    return(paste0("The exposure ", exposure, " has fewer than two observed levels", suffix))
  }
  outcome_values <- outcome_values[!is.na(outcome_values)]
  if (is.numeric(outcome_values) && !all(is.finite(outcome_values))) {
    return(paste0("The outcome ", outcome, " contains non-finite values", suffix))
  }
  if (length(unique(outcome_values)) < 2L) {
    return(paste0("The outcome ", outcome, " has fewer than two observed values", suffix))
  }
  NULL
}

nis_study_model_data_status <- function(data, outcome, exposure, formula = NULL) {
  status <- nis_study_model_input_status(data, outcome, exposure)
  if (!is.null(status)) {
    return(status)
  }
  suffix <- if (is.null(formula)) "." else " in the complete-case rows."
  model_frame <- data
  outcome_values <- data[[outcome]]
  if (!is.null(formula)) {
    result <- nis_study_formula_status(data, formula)
    if (!is.null(result$status)) {
      return(result$status)
    }
    model_frame <- result$model_frame
    outcome_values <- result$outcome_values
  }
  nis_study_variable_status(model_frame, outcome_values, outcome, exposure, suffix)
}

nis_study_run_model <- function(formula, design, family, fit) {
  captured <- new.env(parent = emptyenv())
  captured$warnings <- character()
  model <- tryCatch(
    withCallingHandlers(
      fit(formula, design = design, family = family),
      warning = function(warning) {
        captured$warnings <- c(captured$warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error) error
  )
  list(model = model, warnings = captured$warnings)
}

nis_study_warning_status <- function(warnings) {
  material_warning <- grepl(
    paste0(
      "did not converge|failed to converge|not converged|iteration limit|",
      "fitted probabilities.*(0 or 1|numerically)|non[- ]finite|nonfinite|",
      "NaNs? produced|perfect separation"
    ),
    warnings,
    ignore.case = TRUE
  )
  if (any(material_warning)) {
    return(paste("The model fit is unstable:", paste(unique(warnings[material_warning]), collapse = "; ")))
  }
  NULL
}

nis_study_estimate_status <- function(model) {
  coefficients <- tryCatch(stats::coef(model), error = function(error) NULL)
  if (is.null(coefficients) || length(coefficients) == 0L || !all(is.finite(coefficients))) {
    return("The model returned missing or non-finite coefficients.")
  }
  covariance <- tryCatch(stats::vcov(model), error = function(error) NULL)
  if (is.null(covariance) || length(covariance) == 0L || !all(is.finite(covariance))) {
    return("The model returned missing or non-finite covariance estimates.")
  }
  NULL
}

nis_study_fit_model <- function(formula, design, family, fit = survey::svyglm, outcome = NULL, exposure = NULL) {
  if (!is.null(outcome) || !is.null(exposure)) {
    status <- nis_study_model_data_status(design$variables, outcome, exposure, formula)
    if (!is.null(status)) {
      return(list(model = NULL, status = status, warnings = character()))
    }
  }
  result <- nis_study_run_model(formula, design, family, fit)
  model <- result$model
  warnings <- result$warnings
  if (inherits(model, "error")) {
    return(list(model = NULL, status = paste("Model fit failed:", conditionMessage(model)), warnings = warnings))
  }
  if (identical(model$converged, FALSE)) {
    return(list(model = NULL, status = "The model did not converge.", warnings = warnings))
  }
  status <- nis_study_warning_status(warnings)
  if (is.null(status)) {
    status <- nis_study_estimate_status(model)
  }
  if (!is.null(status)) {
    return(list(model = NULL, status = status, warnings = warnings))
  }
  list(model = model, status = NULL, warnings = warnings)
}
