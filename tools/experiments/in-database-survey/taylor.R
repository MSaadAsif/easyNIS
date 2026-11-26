# Inputs to this experiment are trusted SQL expressions over the valid view.
`%||%` <- function(x, default) if (is.null(x)) default else x
double_sql <- function(x) sprintf("nullif(CAST((%s) AS DOUBLE), 'NaN'::DOUBLE)", x)
keys <- "YEAR, NIS_STRATUM, HOSP_NIS"

cross_terms <- function(columns, weight) {
  pairs <- which(upper.tri(matrix(FALSE, length(columns), length(columns)),
    diag = TRUE), arr.ind = TRUE)
  sprintf("fsum((%s) * %s * %s) AS a%d", weight, columns[pairs[, 1L]],
    columns[pairs[, 2L]], seq_len(nrow(pairs)))
}

cross_matrix <- function(values, p) {
  out <- matrix(0, p, p)
  out[upper.tri(out, diag = TRUE)] <- as.numeric(values)
  out[lower.tri(out)] <- t(out)[lower.tri(out)]
  out
}

taylor_variance_sql <- function(columns, group = NULL) {
  strata <- paste(c("YEAR", "NIS_STRATUM", group), collapse = ", ")
  population <- if (is.null(group)) "()" else paste("(PARTITION BY", group, ")")
  policy <- getOption("survey.lonely.psu", "fail")
  if (!policy %in% c("fail", "adjust")) stop("Unsupported lonely PSU policy.")
  adjust <- if (policy != "adjust") "false" else if (isTRUE(getOption("survey.adjust.domain.lonely"))) {
    "n_active = 1"
  } else {
    "n_psu = 1"
  }
  # Survey omits entirely inactive strata and pads represented strata to their
  # original PSU counts. The adjustment centers active singletons on that sample.
  center <- sprintf(paste(
    "CASE WHEN n_active = 0 THEN 0 WHEN %2$s THEN %1$s -",
    "fsum(%1$s) OVER %3$s / count(*) FILTER (WHERE n_active > 0) OVER %3$s",
    "ELSE %1$s - favg(%1$s) OVER (PARTITION BY %4$s) END AS %1$s_center"),
    columns, adjust, population, strata)
  paste("counts AS (SELECT *, count(*) OVER (PARTITION BY", strata, ") AS n_psu,",
    "count(*) FILTER (WHERE active) OVER (PARTITION BY", strata, ") AS n_active FROM linearized),",
    "centered AS (SELECT *, CASE WHEN n_psu = 1 THEN 1 ELSE n_psu / (n_psu - 1) END AS scale,",
    paste(center, collapse = ", "), "FROM counts)")
}

check_lonely <- function(value) {
  if (getOption("survey.lonely.psu", "fail") == "fail" && any(value, na.rm = TRUE)) {
    stop("Active sample stratum has one PSU.")
  }
}

taylor_stat <- function(query, outcome, total = FALSE, domain = "true",
                        group = NULL, na.rm = TRUE, weight = "DISCWT") {
  rows <- sprintf("SELECT %s, %s AS y, %s AS grp, %s AS w,
    coalesce((%s), false) AS inside FROM valid", keys, double_sql(outcome),
    double_sql(group %||% "0"), double_sql(weight), domain)
  # Center the record-level outcome before aggregating by PSU. Subtracting
  # weighted totals of two nearly equal large values loses the influence.
  anchor <- if (total) "SELECT 0::DOUBLE AS origin" else
    "SELECT grp AS anchor_grp, coalesce(favg(y) FILTER (WHERE inside), 0) AS origin FROM rows GROUP BY grp"
  join <- if (total) "CROSS JOIN anchor" else "JOIN anchor ON grp IS NOT DISTINCT FROM anchor_grp"
  levels <- if (is.null(group)) "SELECT 0::DOUBLE AS grp" else
    "SELECT DISTINCT grp FROM observed WHERE domain_n > 0 AND grp IS NOT NULL"
  result <- query(sprintf(paste(
    "WITH rows AS NOT MATERIALIZED (%s), anchor AS (%s),",
    "observed AS MATERIALIZED (SELECT %s, grp,",
    "count(*) FILTER (WHERE inside) AS domain_n,",
    "count(*) FILTER (WHERE inside AND y IS NULL) AS missing_n,",
    "count(*) FILTER (WHERE inside AND y IS NOT NULL) AS complete_n,",
    "coalesce(fsum(w * (y - origin)) FILTER (WHERE inside), 0) AS wy,",
    "coalesce(fsum(w) FILTER (WHERE inside AND y IS NOT NULL), 0) AS w,",
    "bool_or(inside AND (w IS NULL OR NOT isfinite(w) OR w <= 0)) AS invalid_weight",
    "FROM rows %s GROUP BY ALL),",
    "psus AS (SELECT DISTINCT %s FROM observed), groups AS (%s),",
    "padded AS (SELECT %s, grp, coalesce(wy, 0) AS wy, coalesce(w, 0) AS w,",
    "coalesce(missing_n, 0) AS missing_n, coalesce(invalid_weight, false) AS invalid_weight,",
    "coalesce(%s, 0) > 0 AS active FROM (psus CROSS JOIN groups)",
    "LEFT JOIN observed USING (%s, grp)),",
    "totals AS (SELECT grp, fsum(wy) AS numerator, fsum(w) AS denominator,",
    "bool_or(missing_n > 0) AS any_missing FROM padded GROUP BY grp),",
    "linearized AS (SELECT *, %s AS u FROM padded JOIN totals USING (grp)), %s",
    "SELECT grp, any_value(%s) AS estimate,",
    "sqrt(coalesce(fsum(scale * u_center * u_center), 0)) AS se,",
    "bool_or(n_psu = 1 AND active) AS lonely, bool_or(%s) AS missing,",
    "bool_or(invalid_weight) AS invalid_weight FROM centered %s GROUP BY grp ORDER BY grp"),
    rows, anchor, keys, join, keys, levels, keys,
    if (na.rm) "complete_n" else "domain_n", keys,
    if (total) "wy" else "CASE WHEN denominator > 0 THEN (wy - w * numerator / denominator) / denominator ELSE 0 END",
    taylor_variance_sql("u", "grp"),
    if (total) "numerator" else "coalesce(origin + numerator / nullif(denominator, 0), 0)",
    if (na.rm) "false" else "any_missing", if (total) "" else "LEFT JOIN anchor ON grp = anchor_grp"))
  if (any(result$invalid_weight)) stop("Analysis weights must be finite and positive.")
  check_lonely(result$lonely)
  result[result$missing, c("estimate", "se")] <- NA_real_
  term <- if (is.null(group)) outcome else as.character(result$grp)
  list(estimate = stats::setNames(result$estimate, term),
    se = stats::setNames(result$se, term))
}

linear_predictor <- function(x, beta) {
  paste(sprintf("%s * CAST('%.17g' AS DOUBLE)", x, beta), collapse = " + ")
}

working_model <- function(family, x, beta, eta = "eta", mu = "mu") {
  predictor <- if (!is.null(beta)) linear_predictor(x, beta) else switch(family,
    gaussian = "y", quasibinomial = "ln((w * y + 0.5) / (w * (1 - y) + 0.5))",
    poisson = "ln(y + 0.1)")
  response <- switch(family, gaussian = eta,
    quasibinomial = sprintf(paste(
      "CASE WHEN %1$s > 30 THEN 0.9999999999999998 WHEN %1$s < -30",
      "THEN 2.220446049250313e-16 ELSE 1 / (1 + exp(-%1$s)) END"), eta),
    poisson = sprintf("greatest(2.220446049250313e-16, exp(%s))", eta))
  derivative <- switch(family, gaussian = "1.0::DOUBLE",
    quasibinomial = sprintf(paste(
      "CASE WHEN abs(%1$s) > 30 THEN 2.220446049250313e-16",
      "ELSE exp(-abs(%1$s)) / pow(1 + exp(-abs(%1$s)), 2) END"), eta),
    poisson = mu)
  deviance <- switch(family, gaussian = "(y - mu) * (y - mu)",
    quasibinomial = "-2 * CASE WHEN y = 1 THEN ln(mu) ELSE ln(1 - mu) END",
    poisson = "2 * (CASE WHEN y = 0 THEN 0 ELSE y * ln(y / mu) END - (y - mu))")
  list(eta = predictor, mu = response, derivative = derivative, deviance = deviance)
}

wls_inverse <- function(info) {
  scale <- sqrt(diag(info))
  if (any(!is.finite(scale) | scale <= 0)) stop("Rank deficient model matrix.")
  scaled <- info / outer(scale, scale)
  # Pivoted Cholesky is a rank check on the scaled Gram matrix. Its tolerance
  # must also account for the precision lost by forming the Gram matrix.
  factor <- suppressWarnings(chol(scaled, pivot = TRUE))
  if (attr(factor, "rank") != nrow(info)) stop("Rank deficient model matrix.")
  permutation <- order(attr(factor, "pivot"))
  chol2inv(factor)[permutation, permutation] / outer(scale, scale)
}

taylor_glm <- function(query, outcome, predictors, family, domain = "true",
                       weight = "DISCWT", epsilon = glm.control()$epsilon,
                       maxit = glm.control()$maxit, materialize = NULL) {
  term_names <- names(predictors)
  p <- length(predictors)
  x <- paste0("x", seq_len(p))
  q <- p * (p + 1L) / 2L
  projected <- sprintf("SELECT %s, %s AS y, %s AS raw_w, %s FROM valid WHERE coalesce((%s), false)",
    keys, double_sql(outcome), double_sql(weight),
    paste(sprintf("%s AS %s", double_sql(predictors), x), collapse = ", "), domain)
  projected <- if (is.null(materialize)) paste0("(", projected, ")") else materialize(projected)
  w <- query(paste("SELECT favg(raw_w) AS scale,",
    "bool_or(raw_w IS NULL OR NOT isfinite(raw_w) OR raw_w <= 0) AS bad FROM", projected))
  if (isTRUE(w$bad) || !is.finite(w$scale)) stop("Analysis weights must be finite and positive.")
  complete <- paste(sprintf("%s IS NOT NULL", c("y", x)), collapse = " AND ")
  base <- sprintf("WITH model_rows AS (SELECT *, raw_w / CAST('%.17g' AS DOUBLE) AS w FROM %s WHERE %s)",
    w$scale, projected, complete)
  family_check <- switch(family, gaussian = "false", quasibinomial = "y NOT IN (0, 1)",
    poisson = "y < 0")
  system_at <- function(beta) {
    model <- working_model(family, x, beta)
    query(sprintf(paste(
      "%s, eta_rows AS (SELECT *, %s AS eta FROM model_rows),",
      "means AS (SELECT *, %s AS mu FROM eta_rows),",
      "working AS (SELECT *, (%s) AS d, CASE WHEN isfinite(mu) AND isfinite(eta)",
      "THEN (%s) ELSE 'Infinity'::DOUBLE END AS dev FROM means)",
      "SELECT %s, %s, fsum(w * dev) AS deviance,",
      "bool_or(%s OR NOT isfinite(y) OR %s) AS bad,",
      "bool_and((eta > 0) = (y = 1)) AS perfect,",
      "max(abs(eta)) AS max_eta FROM working"),
      base, model$eta, model$mu, model$derivative, model$deviance,
      paste(cross_terms(x, "w * d"), collapse = ", "),
      paste(sprintf("fsum(%s * w * (d * eta + y - mu)) AS rhs%d", x, seq_len(p)),
        collapse = ", "), family_check, paste(sprintf("NOT isfinite(%s)", x), collapse = " OR ")))
  }
  beta <- NULL
  system <- system_at(beta)
  if (isTRUE(system$bad) || !is.finite(system$deviance)) stop("Invalid or empty complete model rows.")
  converged <- FALSE
  for (iteration in seq_len(maxit)) {
    inverse <- wls_inverse(cross_matrix(system[seq_len(q)], p))
    previous <- beta
    beta <- drop(inverse %*% as.numeric(system[q + seq_len(p)]))
    if (any(!is.finite(beta))) stop("IRLS produced non-finite coefficients.")
    # Identity-link Gaussian has a fixed working system. Its second WLS
    # iteration repeats the first; the score pass determines the iteration count.
    if (family == "gaussian") {
      converged <- TRUE
      break
    }
    next_system <- system_at(beta)
    halves <- 0L
    while (!is.finite(next_system$deviance) && !is.null(previous) && halves < maxit) {
      beta <- (beta + previous) / 2
      next_system <- system_at(beta)
      halves <- halves + 1L
    }
    dev <- next_system$deviance
    if (!is.finite(dev)) stop("IRLS did not converge after step halving.")
    if (family == "quasibinomial" && (isTRUE(next_system$perfect) || next_system$max_eta > 30)) {
      stop("Complete or possible quasi separation in the quasibinomial model.")
    }
    if (abs(dev - system$deviance) / (0.1 + abs(dev)) < epsilon) {
      converged <- TRUE
      break
    }
    system <- next_system
  }
  if (!converged) stop("IRLS did not converge.")
  final <- working_model(family, x, beta)
  prior <- working_model(family, x, previous, "prior_eta", "prior_mu")
  gaussian_dev <- if (family == "gaussian") ", fsum(w * (y - mu) * (y - mu)) AS dev" else ""
  final_dev <- if (family == "gaussian") ", fsum(dev) AS deviance" else ""
  s <- paste0("s", seq_len(p))
  # glm.fit pairs the final residual with the working weights of the last WLS
  # step. Evaluate scores only on the model rows, before joining the PSU roster.
  result <- query(sprintf(paste(
    "%s, eta_rows AS (SELECT *, %s AS eta, %s AS prior_eta FROM model_rows),",
    "means AS (SELECT *, %s AS mu, %s AS prior_mu FROM eta_rows),",
    "scores AS (SELECT *, w * (%s) * (y - mu) / (%s) AS score FROM means),",
    "observed AS (SELECT %s, true AS active, %s %s FROM scores GROUP BY %s),",
    "psus AS (SELECT DISTINCT %s FROM valid),",
    "linearized AS (SELECT %s, coalesce(active, false) AS active, %s %s",
    "FROM psus LEFT JOIN observed USING (%s)), %s",
    "SELECT %s, bool_or(active AND n_psu = 1) AS lonely,",
    "count(*) FILTER (WHERE active) -",
    "count(DISTINCT (YEAR, NIS_STRATUM)) FILTER (WHERE active) AS design_df %s FROM centered"),
    base, final$eta, prior$eta, final$mu, prior$mu, prior$derivative, final$derivative,
    keys, paste(sprintf("fsum(%s * score) AS %s", x, s), collapse = ", "), gaussian_dev,
    keys, keys, keys, paste(sprintf("coalesce(%1$s, 0) AS %1$s", s), collapse = ", "),
    if (family == "gaussian") ", dev" else "", keys, taylor_variance_sql(s),
    paste(cross_terms(paste0(s, "_center"), "scale"), collapse = ", "), final_dev))
  check_lonely(result$lonely)
  if (family == "gaussian") {
    if (!is.finite(result$deviance)) stop("Gaussian fit produced non-finite deviance.")
    if (result$deviance / (0.1 + abs(result$deviance)) >= epsilon) {
      if (maxit < 2L) stop("IRLS did not converge.")
      iteration <- 2L
    }
  }
  vcov <- inverse %*% cross_matrix(result[seq_len(q)], p) %*% inverse
  if (any(!is.finite(vcov))) stop("Non-finite model covariance.")
  dimnames(vcov) <- list(term_names, term_names)
  list(estimate = stats::setNames(beta, term_names), se = sqrt(diag(vcov)),
    vcov = vcov, df = as.numeric(result$design_df) + 1 - p, iterations = iteration)
}
