test_that("profile contrasts use independent hospital covariance with interactions and explicit df", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$y[rows$HOSP_NIS == "0004"] <- NA
  design <- model_design(session, rows)
  design$design$variables$group <- factor(rows$group)
  rows$group <- factor(rows$group)
  domain <- nis_domain(design, "domain", "fail")
  keep <- rows$domain & !is.na(rows$y)
  formula <- y ~ x * group
  reference <- model_sandwich(rows, formula, stats::gaussian(), keep)
  profiles <- stats::model.matrix(~ x * group, data.frame(x = c(-1, 2),
    group = factor(c(0, 1), levels = levels(rows$group))))
  weights <- profiles[2L, ] - profiles[1L, ]
  expected <- unname(sum(weights * reference$coefficients))
  variance <- unname(drop(weights %*% reference$covariance %*% weights))
  for (df in c(6, Inf)) {
    fit <- fit_invented(domain, formula, missing = "exclude", df = df)
    before <- fit
    result <- nis_model_contrast(fit, weights[weights != 0], "mean_difference")
    critical <- if (is.infinite(df)) stats::qnorm(0.95) else stats::qt(0.95, df)
    statistic <- expected / sqrt(variance)
    p <- if (is.infinite(df)) 2 * stats::pnorm(abs(statistic), lower.tail = FALSE) else
      2 * stats::pt(abs(statistic), df, lower.tail = FALSE)
    expect_lt(abs(result$estimate - expected), 1e-10)
    expect_lt(abs(result$link_variance - variance), 1e-10)
    expect_lt(abs(result$effect_se - sqrt(variance)), 1e-10)
    expect_equal(result$link_se, result$effect_se)
    expect_lt(abs(result$lower - (expected - critical * sqrt(variance))), 1e-10)
    expect_lt(abs(result$upper - (expected + critical * sqrt(variance))), 1e-10)
    expect_lt(abs(result$statistic - statistic), 1e-10)
    expect_lt(abs(result$p_value - p), 1e-10)
    expect_equal(result$df, df)
    expect_equal(result$confidence, fit$provenance$confidence)
    expect_equal(result$contrast, weights)
    expect_identical(result$model, before)
    expect_identical(fit, before)
    expect_identical(result$sample, fit$sample)
    expect_identical(result$factors, fit$factors)
    expect_identical(result$diagnostics, fit$diagnostics)
    expect_identical(result$provenance$model, fit$provenance)
    expect_identical(result$scales$response_expression, "y")
    expect_false(result$provenance$analysis_ready)
    reversed <- nis_model_contrast(fit, -weights, "mean_difference")
    expect_equal(reversed$estimate, -result$estimate)
    expect_equal(reversed$lower, -result$upper)
    expect_equal(reversed$upper, -result$lower)
    expect_equal(reversed$link_se, result$link_se)
    expect_equal(reversed$p_value, result$p_value)
    native <- survey::svycontrast(fit$native, weights)
    expect_equal(result$link_estimate, unname(stats::coef(native)), tolerance = 1e-10)
    expect_equal(result$link_variance, unname(stats::vcov(native)[1L, 1L]), tolerance = 1e-10)
  }
})

test_that("explicit odds, mean and rate ratios match independent link references", {
  session <- nis_open()
  on.exit(nis_close(session))
  first <- model_fixture()
  first$exposure <- rep(c(0.5, 1, 2, 5), 16L)
  second <- first
  second$YEAR <- 2021L
  second$DISCWT <- second$DISCWT * 2.5
  first$count[first$HOSP_NIS == "0004"] <- NA
  second$exposure[second$HOSP_NIS == "0007"] <- NA
  years <- list(model_design(session, first), model_design(session, second))
  pooled <- nis_domain(nis_pool_design(years,
    c("binary", "count", "x", "group", "exposure", "domain"), "combined_total"), "domain", "fail")
  rows <- rbind(first, second)
  for (interpretation in c("odds_ratio", "mean_ratio", "rate_ratio")) {
    family <- if (interpretation == "odds_ratio") "quasibinomial" else "quasipoisson"
    formula <- if (interpretation == "odds_ratio") binary ~ x * group else
      if (interpretation == "rate_ratio") count ~ x * group + offset(log(exposure)) else count ~ x * group
    df <- if (interpretation == "mean_ratio") Inf else 6
    fit <- fit_invented(pooled, formula, family, "exclude", df = df)
    before <- fit
    fields <- all.vars(formula)
    keep <- rows$domain & stats::complete.cases(rows[fields])
    native_family <- if (family == "quasibinomial") stats::quasibinomial() else stats::quasipoisson()
    reference <- model_sandwich(rows, formula, native_family, keep)
    weights <- c("(Intercept)" = 0, x = 2, group = 1, "x:group" = 2)
    link <- unname(sum(weights * reference$coefficients))
    se <- sqrt(unname(drop(weights %*% reference$covariance %*% weights)))
    result <- nis_model_contrast(fit, weights, interpretation)
    critical <- if (is.infinite(df)) stats::qnorm(0.95) else stats::qt(0.95, df)
    p <- if (is.infinite(df)) 2 * stats::pnorm(abs(link / se), lower.tail = FALSE) else
      2 * stats::pt(abs(link / se), df, lower.tail = FALSE)
    expect_lt(abs(result$link_estimate - link), 1e-7)
    expect_lt(abs(result$link_se - se), 1e-7)
    expect_lt(abs(result$estimate - exp(link)), 1e-7)
    expect_lt(abs(result$effect_se - exp(link) * se), 1e-7)
    expect_lt(abs(result$lower - exp(link - critical * se)), 1e-7)
    expect_lt(abs(result$upper - exp(link + critical * se)), 1e-7)
    expect_lt(abs(result$statistic - link / se), 1e-7)
    expect_lt(abs(result$p_value - p), 1e-7)
    expect_identical(result$test_scale, "link")
    expect_equal(result$test_null, 0)
    expect_equal(result$null, 1)
    expect_identical(result$model, before)
    expect_identical(fit, before)
    expect_identical(result$scales$exposure, fit$provenance$offset)
    expect_false(result$scales$offset_difference_included)
    reversed <- nis_model_contrast(fit, -weights, interpretation)
    expect_equal(reversed$estimate, 1 / result$estimate)
    expect_equal(reversed$lower, 1 / result$upper)
    expect_equal(reversed$upper, 1 / result$lower)
    expect_equal(reversed$p_value, result$p_value)
    link_result <- nis_model_contrast(fit, weights, "link_difference")
    expect_equal(link_result$estimate, result$link_estimate)
    expect_equal(link_result$effect_se, result$link_se)
    if (interpretation == "mean_ratio") expect_error(nis_model_contrast(fit, weights, "rate_ratio"), "incompatible")
    if (interpretation == "rate_ratio") expect_error(nis_model_contrast(fit, weights, "mean_ratio"), "incompatible")
  }
})

test_that("contrast declarations refuse invalid names, types, aliases and interpretations", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  fit <- fit_invented(design)
  expect_error(nis_model_contrast(design, c(x = 1), "link_difference"), "nis_model")
  expect_error(nis_model_contrast(fit, c(x = 1)), "explicit")
  for (weights in list(numeric(), 1, c(x = 0), c(x = NA_real_), c(x = Inf), c(x = 1 + 1i),
      c(x = 1, x = 2), stats::setNames(1, ""), stats::setNames(1, NA_character_),
      structure(c(x = 1), class = "invented"), matrix(1, dimnames = list("x", NULL)), c(x = TRUE))) {
    expect_error(nis_model_contrast(fit, weights, "link_difference"), "plain named numeric")
  }
  expect_error(nis_model_contrast(fit, c(unknown = 1), "link_difference"), "match")
  for (interpretation in c("link_difference", "mean_difference", "odds_ratio", "mean_ratio", "rate_ratio")) {
    expect_error(nis_model_contrast(fit, c("(Intercept)" = 1), interpretation), "zero intercept")
  }
  for (interpretation in c("odds_ratio", "mean_ratio", "rate_ratio")) {
    expect_error(nis_model_contrast(fit, c(x = 1), interpretation), "incompatible")
  }
  expect_error(nis_model_contrast(fit, c(x = 1), "risk_ratio"), "Unsupported")
  design$design <- stats::update(design$design, duplicate = x)
  alias <- fit_invented(design, y ~ x + duplicate)
  expect_error(nis_model_contrast(alias, c(duplicate = 1), "link_difference"), "aliased")
  result <- nis_model_contrast(alias, c(x = 1, duplicate = 0), "mean_difference")
  omitted <- nis_model_contrast(alias, c(x = 1), "mean_difference")
  expect_equal(result$estimate, omitted$estimate)
  expect_equal(result$link_se, omitted$link_se)
  expect_equal(result$contrast[["duplicate"]], 0)
  transformed <- fit_invented(design, log1p(abs(y)) ~ x)
  expect_error(nis_model_contrast(transformed, c(x = 1), "mean_difference"), "response scale")
  transformed_result <- nis_model_contrast(transformed, c(x = 1), "link_difference")
  expect_identical(transformed_result$scales$response_expression, "log1p(abs(y))")
  expect_identical(transformed_result$scales$modeled_scale, "transformed_outcome")
  no_intercept <- fit_invented(design, y ~ 0 + x + group)
  expect_equal(nis_model_contrast(no_intercept, c(x = 1), "mean_difference")$estimate,
    unname(stats::coef(no_intercept$native)["x"]))
})

test_that("nonconverged and boundary models remain inspectable only on the link scale", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  design$design$variables$count <- ifelse(design$design$variables$x > 0, 1e60, 0)
  fit <- fit_invented(design, count ~ x, "quasipoisson")
  expect_false(fit$diagnostics$converged)
  expect_error(nis_model_contrast(fit, c(x = 1), "mean_ratio"), "converged nonboundary")
  inspected <- nis_model_contrast(fit, c(x = 1), "link_difference")
  expect_identical(inspected$diagnostics, fit$diagnostics)
  expect_true(is.finite(inspected$link_se))
  fit <- fit_invented(model_design(session, model_fixture()))
  # Exercise the boundary guard separately from native fitting behavior.
  fit$diagnostics$boundary <- TRUE
  expect_error(nis_model_contrast(fit, c(x = 1), "mean_difference"), "converged nonboundary")
  expect_true(nis_model_contrast(fit, c(x = 1), "link_difference")$diagnostics$boundary)
})

test_that("zero variance retains undefined tests and nonfinite arithmetic is refused", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$y <- 0
  fit <- fit_invented(model_design(session, rows), y ~ x)
  result <- nis_model_contrast(fit, c(x = 1), "mean_difference")
  expect_equal(result$estimate, 0)
  expect_equal(result$link_se, 0)
  expect_equal(result$lower, 0)
  expect_equal(result$upper, 0)
  expect_true(is.nan(result$statistic))
  expect_true(is.nan(result$p_value))
  expect_error(nis_model_contrast(fit, c(x = 1e308, "(Intercept)" = 0), "odds_ratio"), "incompatible")
  ordinary <- fit_invented(model_design(session, model_fixture()))
  expect_error(nis_model_contrast(ordinary, c(x = 1e308), "link_difference"), "finite")
  poisson <- fit_invented(model_design(session, model_fixture()), count ~ x, "quasipoisson")
  expect_error(nis_model_contrast(poisson, c(x = 1e7), "mean_ratio"), "finite|positive")
  expect_error(nis_model_contrast(poisson, c(x = -1e7), "mean_ratio"), "finite|positive")
  # Exact numerical boundary fixtures retain a real fit but declare controlled
  # coefficient/covariance values to isolate zero-variance and overflow rules.
  poisson$native$coefficients["x"] <- 0
  poisson$native$cov.unscaled[,] <- 0
  unit <- nis_model_contrast(poisson, c(x = 1), "mean_ratio")
  expect_equal(unit$estimate, 1)
  expect_equal(unit$effect_se, 0)
  expect_equal(c(unit$lower, unit$upper), c(1, 1))
  expect_true(is.nan(unit$p_value))
  poisson$native$coefficients["x"] <- 2
  exact <- nis_model_contrast(poisson, c(x = 1), "mean_ratio")
  expect_equal(exact$statistic, Inf)
  expect_equal(exact$p_value, 0)
  expect_equal(exact$effect_se, 0)
  poisson$native$coefficients["x"] <- -800
  expect_error(nis_model_contrast(poisson, c(x = 1), "mean_ratio"), "positive")
  poisson$native$coefficients["x"] <- -700
  poisson$native$cov.unscaled["x", "x"] <- 2500
  expect_error(nis_model_contrast(poisson, c(x = 1), "mean_ratio"), "positive")
  poisson$native$coefficients["x"] <- 700
  poisson$native$cov.unscaled["x", "x"] <- 100
  expect_error(nis_model_contrast(poisson, c(x = 1), "mean_ratio"), "finite")
  poisson$provenance$confidence <- 1e-10
  poisson$provenance$df <- Inf
  poisson$native$cov.unscaled["x", "x"] <- 1e20
  expect_error(nis_model_contrast(poisson, c(x = 1), "mean_ratio"), "finite")
  poisson$native$cov.unscaled["x", "x"] <- Inf
  expect_error(nis_model_contrast(poisson, c(x = 1), "link_difference"), "finite")
  poisson$native$cov.unscaled["x", "x"] <- -1
  expect_error(nis_model_contrast(poisson, c(x = 1), "link_difference"), "nonnegative")
})

test_that("model coefficient names must be unique even when the duplicate is aliased", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group <- factor(rows$group)
  rows$group1 <- as.numeric(rows$group == 1)
  design <- model_design(session, rows)
  design$design$variables$group <- rows$group
  design$design$variables$group1 <- rows$group1
  expect_error(fit_invented(design, y ~ group + group1), "coefficient names.*unique")
  rows$group1_raw <- seq_len(nrow(rows)) / nrow(rows)
  valid_design <- model_design(session, rows)
  valid_design$design$variables$group <- rows$group
  valid_design$design$variables$group1_raw <- rows$group1_raw
  valid <- fit_invented(valid_design, y ~ group + group1_raw)
  expect_identical(anyDuplicated(valid$coefficients$term), 0L)
})
