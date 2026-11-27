#' @export
summary.nis_survey_glm <- function(object, correlation = FALSE, df.resid = NULL, ...) {
  df <- if (is.null(df.resid)) object$df.residual else df.resid
  errors <- sqrt(diag(object$cov.unscaled))
  t <- object$coefficients / errors
  p <- if (df > 0) 2 * stats::pt(-abs(t), df) else rep(NaN, length(t))
  coefficients <- cbind(Estimate = object$coefficients, `Std. Error` = errors, `t value` = t, `Pr(>|t|)` = p)
  summary <- list(
    call = object$call,
    family = object$family,
    coefficients = coefficients,
    cov.unscaled = object$cov.unscaled,
    cov.scaled = object$cov.unscaled,
    aliased = is.na(object$coefficients),
    df = c(object$rank, df, object$rank)
  )
  if (correlation) {
    summary$correlation <- stats::cov2cor(object$cov.unscaled)
  }
  class(summary) <- "summary.nis_survey_glm"
  summary
}

#' @export
print.summary.nis_survey_glm <- function(x, digits = max(3L, getOption("digits") - 3L), ...) {
  cat("Call:\n")
  print(x$call)
  cat("\nCoefficients:\n")
  stats::printCoefmat(x$coefficients, digits = digits)
  invisible(x)
}

#' @export
print.nis_survey_glm <- function(x, ...) {
  print(summary(x), ...)
  invisible(x)
}

#' @export
confint.nis_survey_glm <- function(object, parm, level = 0.95, method = "Wald", ddf = NULL, ...) {
  if (!identical(method, "Wald")) {
    nis_survey_unsupported("Likelihood intervals")
  }
  NextMethod("confint")
}

#' @exportS3Method stats::model.matrix
model.matrix.nis_survey_glm <- function(object, ...) {
  object$matrix
}

#' @exportS3Method stats::nobs
nobs.nis_survey_glm <- function(object, ...) {
  object$n.complete
}

# A model schema carries terms and levels but has no observation rows.
#' @exportS3Method broom.helpers::model_get_n
model_get_n.nis_survey_glm <- function(model) {
  structure(
    data.frame(term = names(model$coefficients), n_obs = NA_real_),
    N_obs = model$n.complete
  )
}
