# This experiment accepts trusted SQL expressions and uses the "valid" view.
`%||%` <- function(x, default) if (is.null(x)) default else x

cross_terms <- function(columns, weight, prefix = "a") {
  pairs <- which(upper.tri(matrix(FALSE, length(columns), length(columns)),
    diag = TRUE), arr.ind = TRUE)
  sprintf("fsum((%s) * %s * %s) AS %s%d", weight, columns[pairs[, 1L]],
    columns[pairs[, 2L]], prefix, seq_len(nrow(pairs)))
}

cross_matrix <- function(values, p) {
  out <- matrix(0, p, p)
  out[upper.tri(out, diag = TRUE)] <- as.numeric(values)
  out[lower.tri(out)] <- t(out)[lower.tri(out)]
  out
}

taylor_center <- function(columns, by = character()) {
  window <- paste(c("YEAR", "NIS_STRATUM", by), collapse = ", ")
  sprintf(paste(
    "SELECT *, count(*) OVER (PARTITION BY %1$s) AS n_psu,",
    "%2$s FROM linearized"), window,
    paste(sprintf("%1$s - favg(%1$s) OVER (PARTITION BY %2$s) AS %1$s_center",
      columns, window), collapse = ", "))
}

taylor_stat <- function(query, outcome, total = FALSE, domain = "true",
                        group = NULL, na.rm = TRUE) {
  ratio <- if (total) "numerator" else "numerator / nullif(denominator, 0)"
  linearized <- if (total) "wy" else "(wy - w * estimate) / nullif(denominator, 0)"
  missing <- if (na.rm) "false" else "any_missing"
  levels <- if (is.null(group)) "SELECT 0 AS grp" else
    "SELECT DISTINCT grp FROM observed WHERE domain_n > 0"
  result <- query(sprintf(paste(
    "WITH rows AS (SELECT YEAR, NIS_STRATUM, HOSP_NIS, DISCWT, (%s) AS y,",
    "(%s) AS grp, coalesce((%s), false) AS inside FROM valid),",
    "observed AS MATERIALIZED (SELECT YEAR, NIS_STRATUM, HOSP_NIS, grp,",
    "count(*) FILTER (WHERE inside) AS domain_n,",
    "count(*) FILTER (WHERE inside AND y IS NULL) AS missing_n,",
    "coalesce(fsum(DISCWT * y) FILTER (WHERE inside), 0) AS wy,",
    "coalesce(fsum(DISCWT) FILTER (WHERE inside AND y IS NOT NULL), 0) AS w",
    "FROM rows GROUP BY ALL),",
    "psus AS (SELECT DISTINCT YEAR, NIS_STRATUM, HOSP_NIS FROM observed),",
    "groups AS (%s),",
    "padded AS (SELECT YEAR, NIS_STRATUM, HOSP_NIS, grp, coalesce(wy, 0) AS wy,",
    "coalesce(w, 0) AS w, coalesce(missing_n, 0) AS missing_n",
    "FROM (psus CROSS JOIN groups) LEFT JOIN observed USING (YEAR, NIS_STRATUM, HOSP_NIS, grp)),",
    "totals AS (SELECT grp, fsum(wy) AS numerator, fsum(w) AS denominator,",
    "bool_or(missing_n > 0) AS any_missing FROM padded GROUP BY grp),",
    "ratios AS (SELECT *, %s AS estimate FROM totals),",
    "linearized AS (SELECT *, %s AS u FROM padded JOIN ratios USING (grp)),",
    "centered AS (%s)",
    "SELECT grp, any_value(estimate) AS estimate,",
    "sqrt(coalesce(fsum(n_psu / nullif(n_psu - 1, 0) * u_center * u_center), 0)) AS se,",
    "bool_or(n_psu = 1 AND w > 0) AS lonely, bool_or(%s) AS missing",
    "FROM centered GROUP BY grp ORDER BY grp"),
    outcome, group %||% "0", domain, levels, ratio, linearized,
    taylor_center("u", "grp"), missing))
  if (any(result$lonely & !result$missing)) stop("Active sample stratum has one PSU.")
  result[result$missing, c("estimate", "se")] <- NA_real_
  keys <- if (is.null(group)) outcome else as.character(result$grp)
  list(estimate = stats::setNames(result$estimate, keys),
    se = stats::setNames(result$se, keys))
}

linear_predictor <- function(x, beta) {
  paste(sprintf("%s * (%.17g)", x, beta), collapse = " + ")
}

working_model <- function(family, x, beta) {
  # Use the family initializers from glm.fit when no coefficients are supplied.
  eta <- if (!is.null(beta)) linear_predictor(x, beta) else switch(family,
    gaussian = "y", quasibinomial = "ln((w * y + 0.5) / (w * (1 - y) + 0.5))",
    poisson = "ln(y + 0.1)")
  mu <- switch(family, gaussian = "eta",
    quasibinomial = "greatest(2.220446049250313e-16, least(0.9999999999999998, 1 / (1 + exp(-eta))))",
    poisson = "greatest(2.220446049250313e-16, exp(eta))")
  derivative <- switch(family, gaussian = "1.0", quasibinomial = "mu * (1 - mu)", poisson = "mu")
  deviance <- switch(family, gaussian = "(y - mu) * (y - mu)",
    quasibinomial = "-2 * CASE WHEN y = 1 THEN ln(mu) ELSE ln(1 - mu) END",
    poisson = "2 * (CASE WHEN y = 0 THEN 0 ELSE y * ln(y / mu) END - (y - mu))")
  list(eta = eta, mu = mu, derivative = derivative, deviance = deviance)
}

taylor_glm <- function(query, outcome, predictors, family, domain = "true",
                       epsilon = 1e-10, maxit = 25L) {
  term_names <- names(predictors)
  p <- length(predictors)
  x <- paste0("x", seq_len(p))
  q <- p * (p + 1L) / 2L
  base <- sprintf(paste(
    "WITH rows AS (SELECT YEAR, NIS_STRATUM, HOSP_NIS, DISCWT AS w,",
    "(%s) AS y, (%s) AS inside, %s FROM valid),",
    "marked AS (SELECT *, coalesce(inside, false) AND y IS NOT NULL AND %s AS used FROM rows)"),
    outcome, domain, paste(sprintf("(%s) AS %s", predictors, x), collapse = ", "),
    paste(sprintf("%s IS NOT NULL", x), collapse = " AND "))
  beta <- previous <- NULL
  old_deviance <- Inf
  for (iteration in 0:maxit) {
    model <- working_model(family, x, beta)
    system <- query(sprintf(paste(
      "%s, eta_rows AS (SELECT *, %s AS eta FROM marked WHERE used),",
      "means AS (SELECT *, %s AS mu FROM eta_rows),",
      "working AS (SELECT *, (%s) AS d, (%s) AS dev FROM means)",
      "SELECT %s, %s, fsum(w * dev) AS deviance FROM working"),
      base, model$eta, model$mu, model$derivative, model$deviance,
      paste(cross_terms(x, "w * d"), collapse = ", "),
      paste(sprintf("fsum(%s * w * (d * eta + y - mu)) AS rhs%d", x, seq_len(p)),
        collapse = ", ")))
    dev <- system$deviance
    if (!is.finite(dev)) stop("Non-finite deviance or no complete model rows.")
    if (abs(dev - old_deviance) / (0.1 + abs(dev)) < epsilon) break
    if (iteration == maxit) stop("IRLS did not converge.")
    info <- cross_matrix(system[seq_len(q)], p)
    scale <- sqrt(diag(info))
    inverse <- chol2inv(chol(info / outer(scale, scale))) / outer(scale, scale)
    previous <- beta
    beta <- drop(inverse %*% as.numeric(system[q + seq_len(p)]))
    old_deviance <- dev
  }
  prior <- working_model(family, x, previous)
  s <- paste0("s", seq_len(p))
  # glm.fit returns the final residual with the weights of the last WLS step.
  # Keep every sampled PSU for variance, but count only complete PSUs for df.
  result <- query(sprintf(paste(
    "%s, eta_rows AS (SELECT *, %s AS eta, %s AS prior_eta FROM marked),",
    "means AS (SELECT *, %s AS mu, %s AS prior_mu FROM eta_rows),",
    "scores AS (SELECT *, CASE WHEN used THEN w * (%s) * (y - mu) / (%s)",
    "ELSE 0 END AS score FROM means),",
    "linearized AS (SELECT YEAR, NIS_STRATUM, HOSP_NIS, bool_or(used) AS active,",
    "%s FROM scores GROUP BY YEAR, NIS_STRATUM, HOSP_NIS),",
    "centered AS (%s)",
    "SELECT %s, bool_or(active AND n_psu = 1) AS lonely,",
    "count(*) FILTER (WHERE active) -",
    "count(DISTINCT (YEAR, NIS_STRATUM)) FILTER (WHERE active) AS design_df FROM centered"),
    base, model$eta, prior$eta, model$mu,
    gsub("eta", "prior_eta", prior$mu, fixed = TRUE),
    gsub("mu", "prior_mu", prior$derivative, fixed = TRUE), model$derivative,
    paste(sprintf("coalesce(fsum(%s * score), 0) AS %s", x, s), collapse = ", "),
    taylor_center(s), paste(cross_terms(paste0(s, "_center"),
      "n_psu / nullif(n_psu - 1, 0)"), collapse = ", ")))
  if (isTRUE(result$lonely)) stop("Active sample stratum has one PSU.")
  vcov <- inverse %*% cross_matrix(result[seq_len(q)], p) %*% inverse
  dimnames(vcov) <- list(term_names, term_names)
  list(estimate = stats::setNames(beta, term_names), se = sqrt(diag(vcov)),
    vcov = vcov, df = as.numeric(result$design_df) + 1 - p, iterations = iteration)
}
