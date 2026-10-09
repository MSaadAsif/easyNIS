model_fixture <- function() {
  rows <- nis_synthetic_data()$core[rep(1L, 64L), ]
  rows$KEY_NIS <- sprintf("%06d", seq_len(64L))
  rows$HOSP_NIS <- rep(sprintf("%04d", 1:8), each = 8L)
  rows$NIS_STRATUM <- rep(1:2, each = 32L)
  rows$DISCWT <- rep(c(2, 3, 4, 5), length.out = 64L)
  rows$x <- rep(c(-2, -1, 0, 1), 16L)
  rows$group <- rep(c(0, 0, 1, 1, 1, 0, 0, 1), 8L)
  rows$y <- 2 + 0.4 * rows$x + rows$group + rep(c(-1, 0, 2, -2, 1, 0, 1, -1), 8L) +
    rep(c(-0.5, 0.2, 0.3, -0.1, 0.6, -0.2, 0.1, 0.4), each = 8L) * (1 + rows$x + rows$group / 2)
  uniform <- ((seq_len(64L) * 37 + seq_len(64L)^2 * 11) %% 101) / 101
  rows$binary <- as.integer(uniform < stats::plogis(-0.4 + 0.2 * rows$x + 0.3 * rows$group))
  rows$count <- (seq_len(64L) * 5 + rep(1:8, each = 8L)) %% 6
  rows$domain <- !rows$HOSP_NIS %in% c("0002", "0006")
  rows
}

model_design <- function(session, rows) {
  path <- write_invented_parquet(session, rows)
  on.exit(unlink(path))
  nis_survey_design(nis_import(session, path, unique(rows$YEAR)),
    intersect(c("y", "binary", "count", "x", "group", "domain", "exposure", "positive", "period"), names(rows)),
    TRUE, "hospital_wr", "fail")
}

fit_invented <- function(design, formula = y ~ x + group, family = "gaussian",
                         missing = "fail", df = 6, confidence = 0.9) {
  nis_model(design, formula, family, missing, df, confidence, "wr_unadjusted")
}

# Independent canonical-link score sandwich across every original hospital.
model_sandwich <- function(rows, formula, family, keep) {
  data <- rows[keep, ]
  weights <- data$DISCWT
  fit <- stats::glm(formula, data = data, family = family, weights = DISCWT / mean(DISCWT),
                    control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
  x <- stats::model.matrix(fit)
  mu <- stats::fitted(fit)
  derivative <- family$mu.eta(fit$linear.predictors)
  bread <- solve(crossprod(x, x * (weights * derivative^2 / family$variance(mu))))
  score <- matrix(0, nrow(rows), ncol(x))
  score[keep, ] <- x * (weights * (stats::model.response(stats::model.frame(fit)) - mu) *
                          derivative / family$variance(mu))
  hospital <- paste(rows$YEAR, rows$HOSP_NIS, sep = ":")
  strata <- paste(rows$YEAR, rows$NIS_STRATUM, sep = ":")
  totals <- rowsum(score, hospital)
  mapping <- strata[match(rownames(totals), hospital)]
  meat <- matrix(0, ncol(x), ncol(x))
  for (stratum in unique(mapping)) {
    values <- totals[mapping == stratum, , drop = FALSE]
    centered <- sweep(values, 2L, colMeans(values))
    meat <- meat + nrow(values) / (nrow(values) - 1L) * crossprod(centered)
  }
  list(coefficients = stats::coef(fit), covariance = bread %*% meat %*% bread)
}

model_native_refinement <- function(native, design) {
  if (native$family$family == "gaussian" || !isTRUE(native$converged) || isTRUE(native$boundary)) return(native)
  start <- stats::coef(native, na.rm = FALSE)
  start[is.na(start)] <- 0
  survey::svyglm(stats::formula(native), design, family = native$family,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L), start = unname(start))
}

