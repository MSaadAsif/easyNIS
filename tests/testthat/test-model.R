test_that("three model families match native fits and independent cluster scores", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$y[rows$HOSP_NIS == "0004"] <- NA
  rows$x[rows$HOSP_NIS == "0008"] <- NA
  design <- model_design(session, rows)
  before <- design
  options_before <- options()[grepl("^survey[.]|^contrasts$|^na.action$", names(options()))]
  for (selected in list(design, nis_domain(design, "domain", "fail"))) {
    for (family in c("gaussian", "quasibinomial", "quasipoisson")) {
      outcome <- switch(family, gaussian = "y", quasibinomial = "binary", quasipoisson = "count")
      formula <- stats::reformulate(c("x", "group"), outcome)
      result <- fit_invented(selected, formula, family, "exclude")
      keep <- rows$KEY_NIS %in% as.character(result$design$variables$KEY_NIS)
      native_family <- switch(family, gaussian = stats::gaussian(),
        quasibinomial = stats::quasibinomial(), quasipoisson = stats::quasipoisson())
      reference <- model_sandwich(rows, formula, native_family, keep)
      native <- survey::svyglm(formula, result$design, family = native_family, na.action = stats::na.fail,
                               control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
      native <- model_native_refinement(native, result$design)
      native_summary <- summary(native, df.resid = 6)
      expect_s3_class(result, "nis_model")
      expect_s3_class(result$native, "svyglm")
      expect_equal(stats::coef(result$native), reference$coefficients, tolerance = 1e-8)
      tolerance <- if (family == "gaussian") 1e-10 else 1e-7
      expect_lt(max(abs(stats::vcov(result$native) - reference$covariance)), tolerance)
      expect_equal(stats::coef(result$native), stats::coef(native), tolerance = 1e-12)
      expect_equal(result$coefficients$se, native_summary$coefficients[, 2L], ignore_attr = TRUE)
      expect_equal(result$coefficients$p_value, native_summary$coefficients[, 4L], ignore_attr = TRUE)
      expect_lt(max(abs(result$coefficients$lower - (unname(reference$coefficients) -
        stats::qt(0.95, 6) * sqrt(diag(reference$covariance))))), tolerance)
      expect_equal(result$sample$included, sum(keep))
      expect_equal(result$sample$weighted_denominator, sum(rows$DISCWT[keep]))
      expect_equal(result$sample$analysis_degrees_of_freedom, survey::degf(result$design))
      expect_identical(result$provenance$design, selected$provenance)
      expect_identical(result$provenance$domains, selected$domains)
      expect_false(result$provenance$analysis_ready)
      expect_length(result$diagnostics$factor_support, 0L)
      expect_length(result$diagnostics$warnings, 0L)
    }
  }
  expect_identical(design, before)
  expect_identical(options()[names(options_before)], options_before)
  gaussian <- fit_invented(design, missing = "exclude")
  expect_equal(gaussian$sample$missing_by_field, c(y = 8, x = 8, group = 0))
  expect_equal(gaussian$sample$excluded_missing, 16)
  expect_equal(gaussian$sample$full_population_degrees_of_freedom, 6)
})

test_that("factor support counts describe supplied and analyzed native levels", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group <- factor(ifelse(rows$HOSP_NIS == "0003", "b", "a"),
    levels = c("a", "b", "unused"))
  rows$logical_group <- rep(c(FALSE, TRUE), 32L)
  rows$logical_group[c(1L, 10L, 33L)] <- NA
  rows$y[rows$HOSP_NIS == "0001"] <- NA
  design <- model_design(session, rows)
  design$design$variables$group <- rows$group
  design$design$variables$logical_group <- rows$logical_group
  selected <- nis_domain(design, "domain", "fail")
  before <- selected
  options_before <- options()[grepl("^survey[.]|^contrasts$|^na.action$", names(options()))]
  fit <- fit_invented(selected, y ~ group + logical_group, missing = "exclude")
  group <- fit$diagnostics$factor_support$group
  expect_identical(group$level, c("a", "b", "unused"))
  expect_equal(as.numeric(group[1L, -1L]), c(40, 31, 110, 4))
  expect_equal(as.numeric(group[2L, -1L]), c(8, 8, 28, 1))
  expect_equal(unname(as.numeric(group[3L, -1L])), c(0, 0, 0, 0))
  logical_support <- fit$diagnostics$factor_support$logical_group
  expect_identical(logical_support$level, c("FALSE", "TRUE"))
  expect_equal(as.numeric(logical_support[1L, -1L]), c(22, 19, 58, 5))
  expect_equal(as.numeric(logical_support[2L, -1L]), c(24, 20, 80, 5))
  expect_identical(fit$factors$group$levels, c("a", "b"))
  reference <- survey::svyglm(y ~ group + logical_group, fit$design,
    family = stats::gaussian(), na.action = stats::na.fail,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
  expect_equal(stats::coef(fit$native), stats::coef(reference))
  expect_equal(stats::vcov(fit$native), stats::vcov(reference))
  expect_equal(fit$native$contrasts, lapply(fit$factors, `[[`, "contrasts"))
  expect_identical(selected, before)
  expect_identical(options()[names(options_before)], options_before)
  expect_equal(fit$sample$missing_by_field, c(y = 8, group = 0, logical_group = 2))
  selected$design$variables[["I(group)"]] <- factor(rep(c("decoy", "other"), 24L),
    levels = c("decoy", "other"))
  collision_fit <- fit_invented(selected, y ~ I(group), missing = "exclude")
  expect_identical(collision_fit$diagnostics$factor_support[["I(group)"]]$level, c("a", "b"))
  expect_equal(collision_fit$diagnostics$factor_support[["I(group)"]]$supplied_rows,
    c(40L, 8L))

  pooled_designs <- lapply(2021:2022, function(year) {
    annual_rows <- rows
    annual_rows$YEAR <- year
    annual <- model_design(session, annual_rows)
    annual$design$variables$group <- factor(annual_rows$group,
      levels = c("a", "b", "unused"))
    annual
  })
  pooled <- nis_pool_design(pooled_designs, c("y", "group"), "average_annual_total")
  pooled_fit <- fit_invented(pooled, y ~ group, missing = "exclude")
  pooled_group <- pooled_fit$diagnostics$factor_support$group
  expect_identical(pooled_group$level, c("a", "b", "unused"))
  expect_equal(pooled_group$analysis_hospitals, c(12, 2, 0))
  expect_equal(pooled_group$analysis_weight, c(168, 28, 0))
  expect_equal(pooled_fit$sample$excluded_missing, 16L)
  logical_expression_fit <- fit_invented(selected, y ~ I(logical_group), missing = "exclude")
  expect_identical(logical_expression_fit$diagnostics$factor_support[["I(logical_group)"]],
    logical_support)
})

test_that("rare outcomes and sparse factors retain independent domain covariance", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$binary <- 0L
  rows$binary[c(6, 23, 40, 53)] <- 1L
  rows$count <- 0
  rows$count[c(6, 23, 40, 53)] <- 1:4
  rows$group <- as.integer(seq_len(64L) %in% c(6, 17, 40, 49))
  design <- model_design(session, rows)
  rows$group <- factor(rows$group)
  design$design$variables$group <- rows$group
  before <- design
  for (selected in list(design, nis_domain(design, "domain", "fail"))) {
    for (family in c("quasibinomial", "quasipoisson")) {
      formula <- stats::reformulate(c("x", "group"),
        if (family == "quasibinomial") "binary" else "count")
      fit <- fit_invented(selected, formula, family)
      keep <- rows$KEY_NIS %in% as.character(fit$design$variables$KEY_NIS)
      native_family <- if (family == "quasibinomial") stats::quasibinomial() else stats::quasipoisson()
      reference <- model_sandwich(rows, formula, native_family, keep)
      expect_equal(stats::coef(fit$native), reference$coefficients, tolerance = 1e-8)
      expect_lt(max(abs(stats::vcov(fit$native) - reference$covariance)), 1e-7)
      expect_lt(max(abs(fit$coefficients$lower - (unname(reference$coefficients) -
        stats::qt(0.95, 6) * sqrt(diag(reference$covariance))))), 1e-7)
      expect_true(fit$diagnostics$converged)
      expect_true(fit$diagnostics$refined)
      expect_identical(fit$diagnostics$iterations, fit$native$iter)
      expect_equal(fit$provenance$fitting_control, list(epsilon = 1e-10, maxit = 50L))
      expect_equal(fit$diagnostics$rank, 3L)
      expect_length(fit$diagnostics$warnings, 0L)
      expect_identical(fit$factors$group$levels, c("0", "1"))
      expect_identical(fit$factors$group$zero_coded_levels, "0")
      expect_equal(fit$sample$full_population_degrees_of_freedom, 6)
      expect_equal(fit$sample$included, sum(keep))
      expect_identical(fit$design$variables$group, rows$group[keep])
    }
  }
  expect_identical(design, before)
})

test_that("quasi-family refinement preserves exact aliases and missing domains", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$x[rows$HOSP_NIS == "0004"] <- NA
  design <- model_design(session, rows)
  design$design <- stats::update(design$design, duplicate = x)
  before <- design
  for (selected in list(design, nis_domain(design, "domain", "fail"))) {
    for (family in c("quasibinomial", "quasipoisson")) {
      outcome <- if (family == "quasibinomial") "binary" else "count"
      alias <- fit_invented(selected, stats::reformulate(c("x", "duplicate", "group"), outcome),
        family, "exclude")
      reduced <- fit_invented(selected, stats::reformulate(c("x", "group"), outcome), family, "exclude")
      estimable <- !alias$coefficients$aliased
      expect_true(alias$diagnostics$refined)
      expect_identical(alias$diagnostics$aliased, "duplicate")
      expect_equal(alias$diagnostics$rank, 3L)
      expect_true(all(is.na(alias$coefficients[!estimable, c("estimate", "se", "lower", "upper", "p_value")])))
      expect_equal(alias$coefficients[estimable, ], reduced$coefficients, ignore_attr = TRUE, tolerance = 1e-10)
      expect_equal(stats::vcov(alias$native), stats::vcov(reduced$native), tolerance = 1e-10)
      expect_equal(alias$sample$excluded_missing, 8L)
      expect_equal(alias$sample$full_population_degrees_of_freedom, 6)
    }
  }
  expect_identical(design, before)
})

test_that("row-wise transformed outcomes and predictors match independent survey references", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$y <- rows$y + 4
  rows$positive <- abs(rows$x) + rep(c(0.5, 1, 2, 3), each = 16L)
  rows$y[rows$HOSP_NIS == "0004"] <- NA
  rows$positive[rows$HOSP_NIS == "0007"] <- NA
  design <- model_design(session, rows)
  formula <- log1p(y) ~ I(x^2) + log(positive) + group
  for (selected in list(design, nis_domain(design, "domain", "fail"))) {
    fit <- fit_invented(selected, formula, missing = "exclude")
    keep <- stats::complete.cases(rows[c("y", "x", "positive", "group")]) &
      rows$KEY_NIS %in% as.character(selected$design$variables$KEY_NIS)
    reference <- model_sandwich(rows, formula, stats::gaussian(), keep)
    native <- survey::svyglm(formula, fit$design,
      control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
    expect_equal(stats::coef(fit$native), reference$coefficients, tolerance = 1e-10)
    expect_lt(max(abs(stats::vcov(fit$native) - reference$covariance)), 1e-10)
    expect_equal(stats::coef(fit$native), stats::coef(native))
    expect_equal(stats::vcov(fit$native), stats::vcov(native))
    expect_identical(fit$provenance$modeled_scale, "transformed_outcome")
    expect_identical(fit$provenance$response_expression, "log1p(y)")
    expect_identical(fit$provenance$response_fields, "y")
    expect_equal(fit$sample$included, sum(keep))
    expect_equal(fit$sample$missing_by_field, c(y = 8, x = 0, positive = 8, group = 0))
    expect_identical(fit$design$variables$y, rows$y[keep])
    expect_null(fit$provenance$offset)
  }
  shadow <- new.env(parent = environment(formula))
  shadow$log1p <- function(...) stop("caller function must not run")
  shadow$log <- shadow$log1p
  environment(formula) <- shadow
  protected <- fit_invented(design, formula, missing = "exclude")
  expect_s3_class(protected$native, "svyglm")
  prediction <- stats::predict(protected$native, data.frame(x = c(0, 1), positive = c(1, 2), group = c(0, 1)))
  reference_formula <- log1p(y) ~ I(x^2) + log(positive) + group
  reference <- survey::svyglm(reference_formula, protected$design)
  expect_equal(prediction, stats::predict(reference, data.frame(x = c(0, 1), positive = c(1, 2), group = c(0, 1))))
})

test_that("log-exposure offsets retain native scales, exclusions and pooled keys", {
  session <- nis_open()
  on.exit(nis_close(session))
  first <- model_fixture()
  first$exposure <- rep(c(0.5, 1, 2, 5), 16L) * rep(c(1, 2, 3, 1), each = 16L)
  first$positive <- abs(first$x) + 1
  first$period <- 0
  second <- first
  second$YEAR <- 2021L
  second$DISCWT <- second$DISCWT * 2.5
  second$count <- second$count * 1.4
  second$period <- 1
  first$count[first$HOSP_NIS == "0004"] <- NA
  second$exposure[second$HOSP_NIS == "0007"] <- NA
  years <- list(model_design(session, first), model_design(session, second))
  columns <- c("count", "x", "group", "domain", "exposure", "period")
  pooled <- nis_pool_design(years, columns, "combined_total")
  domain <- nis_domain(pooled, "domain", "fail")
  formula <- count ~ x + group + period + offset(log(exposure))
  fit <- fit_invented(domain, formula, "quasipoisson", "exclude")
  all <- rbind(first, second)
  keep <- all$domain & !is.na(all$count) & !is.na(all$exposure)
  reference <- model_sandwich(all, formula, stats::quasipoisson(), keep)
  native <- survey::svyglm(formula, fit$design, family = stats::quasipoisson(),
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
  native <- model_native_refinement(native, fit$design)
  expect_equal(stats::coef(fit$native), reference$coefficients, tolerance = 1e-8)
  expect_lt(max(abs(stats::vcov(fit$native) - reference$covariance)), 1e-7)
  expect_equal(stats::coef(fit$native), stats::coef(native))
  expect_equal(stats::vcov(fit$native), stats::vcov(native))
  expect_equal(fit$native$offset, log(all$exposure[keep]))
  expect_equal(fit$provenance$offset, list(field = "exposure", expression = "log(exposure)", coefficient = 1))
  expect_identical(fit$provenance$response_expression, "count")
  expect_identical(fit$provenance$modeled_scale, "named_outcome")
  expect_equal(fit$sample$missing_by_field, c(count = 8, x = 0, group = 0, period = 0, exposure = 8))
  expect_equal(fit$sample$included, sum(keep))
  expect_equal(fit$sample$full_population_degrees_of_freedom, 12)
  expect_identical(fit$design$variables$exposure, all$exposure[keep])
  scaled <- nis_domain(nis_pool_design(years, columns, "average_annual_total"), "domain", "fail")
  scaled_fit <- fit_invented(scaled, formula, "quasipoisson", "exclude")
  expect_equal(stats::coef(scaled_fit$native), stats::coef(fit$native), tolerance = 1e-10)
  expect_equal(stats::vcov(scaled_fit$native), stats::vcov(fit$native), tolerance = 1e-10)
  linear <- drop(stats::model.matrix(~ x + group + period, all[keep, ]) %*%
    reference$coefficients) + log(all$exposure[keep])
  expect_equal(unname(fit$native$linear.predictors), unname(linear), tolerance = 1e-7)
  expect_equal(unname(fit$native$fitted.values), unname(exp(linear)), tolerance = 1e-7)
  expect_identical(fit$diagnostics$native_offset_prediction, "unsupported")
})

test_that("formula restrictions refuse invalid terms instead of losing observed inputs", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$positive <- abs(rows$x) + 1
  rows$exposure <- 1
  design <- model_design(session, rows)
  for (formula in list(y ~ mean(x), y ~ scale(x), y ~ poly(x, 2), y ~ x[1], y ~ get("x"),
                       y ~ base::log(positive), y ~ offset(exposure), y ~ offset(log(exposure + 1)),
                       y ~ offset(log(exposure)) + offset(log(positive)))) {
    expect_error(fit_invented(design, formula), "supported|unsupported")
  }
  expect_error(fit_invented(design, log1p(binary) ~ x, "quasibinomial"), "Gaussian only")
  expect_error(fit_invented(design, log1p(count) ~ x, "quasipoisson"), "Gaussian only")
  expect_error(fit_invented(design, y ~ x + offset(log(exposure))), "quasipoisson")
  for (value in c(0, -1)) {
    invalid <- design
    invalid$design$variables$exposure[1L] <- value
    invalid$design$variables$x[1L] <- NA
    expect_error(fit_invented(invalid, count ~ x + offset(log(exposure)), "quasipoisson", "exclude"), "positive")
  }
  invalid <- design
  invalid$design$variables$y[1L] <- -2
  invalid$design$variables$x[1L] <- NA
  expect_error(fit_invented(invalid, log1p(y) ~ x, missing = "exclude"), "observed inputs")
  expect_error(fit_invented(design, y ~ I(x / 0)), "Nonfinite|observed inputs")
  invalid <- design
  invalid$design$variables$positive[1L] <- 1e308
  expect_error(fit_invented(invalid, y ~ I(positive^2)), "Nonfinite")
})

test_that("zero estimates and quoted field names keep raw model values", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  design$design$variables[["quoted outcome + x"]] <- 0
  zero <- fit_invented(design, `quoted outcome + x` ~ 1)
  expect_equal(zero$coefficients$estimate, 0)
  expect_equal(zero$coefficients$se, 0)
  expect_equal(zero$coefficients$lower, 0)
  expect_equal(zero$coefficients$upper, 0)
  expect_true(is.nan(zero$coefficients$p_value))
  expect_identical(zero$design$variables, design$design$variables)
  design$design$variables$y[1L] <- -9
  sentinel <- fit_invented(design)
  expect_equal(sentinel$sample$included, 64)
  expect_equal(sentinel$design$variables$y[1L], -9)
})

test_that("finite nonconverged fits retain the native warning for inspection", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  design$design$variables$count <- ifelse(design$design$variables$x > 0, 1e60, 0)
  fit <- fit_invented(design, count ~ x, "quasipoisson")
  captured <- character()
  reference <- withCallingHandlers(survey::svyglm(count ~ x, design$design,
    family = stats::quasipoisson(), na.action = stats::na.fail,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L)), warning = function(w) {
      captured <<- c(captured, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_false(fit$diagnostics$converged)
  expect_false(fit$diagnostics$refined)
  expect_identical(fit$diagnostics$converged, reference$converged)
  expect_true(any(grepl("did not converge", fit$diagnostics$warnings)))
  expect_identical(fit$diagnostics$warnings, captured)
  expect_equal(stats::coef(fit$native), stats::coef(reference))
  expect_false(fit$provenance$analysis_ready)
})

test_that("factor interactions, contrasts, aliases and explicit df remain recoverable", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  design$design <- stats::update(design$design, group = factor(group, levels = c(1, 0), labels = c("yes", "no")))
  fit <- fit_invented(design, y ~ x * group, df = Inf)
  reference <- survey::svyglm(y ~ x * group, design$design)
  expect_equal(stats::coef(fit$native), stats::coef(reference))
  expect_equal(stats::vcov(fit$native), stats::vcov(reference))
  expect_identical(fit$factors$group$levels, c("yes", "no"))
  expect_identical(fit$factors$group$zero_coded_levels, "yes")
  expect_equal(fit$factors$group$contrasts, stats::contr.treatment(c("yes", "no")))
  expect_identical(fit$native$contrasts, list(group = fit$factors$group$contrasts))
  expect_length(fit$diagnostics$warnings, 0L)
  expect_equal(fit$coefficients$upper, fit$coefficients$estimate + stats::qnorm(0.95) * fit$coefficients$se)
  expect_equal(fit$sample$native_residual_degrees_of_freedom, reference$df.residual)
  saved <- options(contrasts = c("contr.sum", "contr.poly"))
  on.exit(options(saved), add = TRUE)
  sum_fit <- fit_invented(design)
  expect_length(sum_fit$factors$group$zero_coded_levels, 0L)
  expect_equal(sum_fit$factors$group$contrasts, stats::contr.sum(c("yes", "no")))
  expect_equal(fit$factors$group$zero_coded_levels, "yes")
  design$design <- stats::update(design$design, duplicate = x)
  alias <- fit_invented(design, y ~ x + duplicate)
  expect_true(any(alias$coefficients$aliased))
  expect_true(all(is.na(alias$coefficients$se[alias$coefficients$aliased])))
  expect_true("duplicate" %in% alias$diagnostics$aliased)
})

test_that("logical predictors retain native FALSE/TRUE coding without changing raw columns", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  raw <- design$design$variables$domain
  fit <- fit_invented(design, y ~ domain)
  expect_identical(fit$factors$domain$levels, c("FALSE", "TRUE"))
  expect_identical(fit$factors$domain$zero_coded_levels, "FALSE")
  expect_identical(fit$native$contrasts, list(domain = fit$factors$domain$contrasts))
  expect_identical(fit$design$variables$domain, raw)
  expect_length(fit$diagnostics$warnings, 0L)
  saved <- options(contrasts = c("contr.sum", "contr.poly"))
  on.exit(options(saved), add = TRUE)
  sum_fit <- fit_invented(design, y ~ domain)
  expect_equal(sum_fit$factors$domain$contrasts, stats::contr.sum(c("FALSE", "TRUE")))
  expect_length(sum_fit$factors$domain$zero_coded_levels, 0L)
  expect_identical(fit$factors$domain$zero_coded_levels, "FALSE")
  binary <- fit_invented(design, domain ~ x, "quasibinomial")
  expect_length(binary$factors, 0L)
})

test_that("pooled reused IDs and missing rows retain independent variance", {
  session <- nis_open()
  on.exit(nis_close(session))
  first <- model_fixture()
  second <- first
  second$YEAR <- 2021L
  second$DISCWT <- second$DISCWT * 3
  second$y <- second$y + 2
  first$y[first$HOSP_NIS == "0003"] <- NA
  second$x[second$HOSP_NIS == "0007"] <- NA
  years <- list(model_design(session, first), model_design(session, second))
  columns <- c("y", "x", "group", "domain")
  combined <- nis_pool_design(years, columns, "combined_total")
  average <- nis_pool_design(years, columns, "average_annual_total")
  all <- rbind(first, second)
  selected <- nis_domain(combined, "domain", "fail")
  fit <- fit_invented(selected, missing = "exclude")
  keep <- all$domain & !is.na(all$y) & !is.na(all$x)
  reference <- model_sandwich(all, y ~ x + group, stats::gaussian(), keep)
  expect_equal(stats::coef(fit$native), reference$coefficients, tolerance = 1e-10)
  expect_equal(unname(stats::vcov(fit$native)), unname(reference$covariance), tolerance = 1e-10)
  scaled <- fit_invented(nis_domain(average, "domain", "fail"), missing = "exclude")
  expect_equal(stats::coef(fit$native), stats::coef(scaled$native), tolerance = 1e-10)
  expect_equal(stats::vcov(fit$native), stats::vcov(scaled$native), tolerance = 1e-10)
  expect_equal(fit$sample$weighted_denominator, scaled$sample$weighted_denominator * 2)
  expect_equal(fit$sample$full_population_degrees_of_freedom, 12)
  expect_equal(fit$provenance$design$years, c(2022L, 2021L))
})

test_that("terms metadata cannot replace the checked formula expressions", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  reference <- fit_invented(design, y ~ x)
  supplied <- stats::terms(y ~ x)
  attr(supplied, "predvars") <- quote(list(abs(y), x * 2))
  before <- supplied
  fit <- fit_invented(design, supplied)
  expect_equal(stats::coef(fit$native), stats::coef(reference$native))
  expect_equal(stats::vcov(fit$native), stats::vcov(reference$native))
  expect_identical(fit$native$y, reference$native$y)
  expect_identical(fit$provenance$response_expression, "y")
  expect_identical(fit$provenance$modeled_scale, "named_outcome")
  expect_identical(supplied, before)
  expect_equal(stats::predict(fit$native, newdata = data.frame(x = 2)),
    stats::predict(reference$native, newdata = data.frame(x = 2)))
})

test_that("invalid formulas, fields and policies fail without caller mutation", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  expect_error(nis_model(design, y ~ x), "explicit")
  for (formula in list(~ x, log(y) ~ x, y ~ log(x), y ~ offset(x), y ~ ., y ~ scale(x),
                       y ~ stats::poly(x, 2), y ~ get("x"))) {
    expect_error(fit_invented(design, formula), "formula|terms|unsupported")
  }
  x_external <- 1:64
  expect_error(fit_invented(design, y ~ x_external), "retained")
  for (field in c(".survey.prob.weights", "(weights)", "(offset)")) {
    reserved <- design
    reserved$design$variables[[field]] <- seq_len(64L)
    expect_error(fit_invented(reserved, stats::as.formula(paste0("`", field, "` ~ x"))), "reserved")
    expect_error(fit_invented(reserved, stats::as.formula(paste0("y ~ `", field, "`"))), "reserved")
  }
  expect_error(fit_invented(design, family = "binomial"), "Unsupported")
  expect_error(fit_invented(design, df = 0), "positive")
  expect_error(fit_invented(design, df = 2 + 1i), "positive")
  expect_error(fit_invented(design, confidence = 1), "confidence")
  invalid <- design
  invalid$design$variables$x[1L] <- Inf
  expect_error(fit_invented(invalid), "Infinite")
  invalid$design$variables$x <- as.character(design$design$variables$x)
  expect_error(fit_invented(invalid), "explicit factors")
  invalid$design$variables$x <- bit64::as.integer64(design$design$variables$x)
  expect_error(fit_invented(invalid), "BIGINT")
  expect_error(fit_invented(design, y ~ x, "quasibinomial"), "zero/one")
  invalid <- design
  invalid$design$variables$count[1L] <- -1
  expect_error(fit_invented(invalid, count ~ x, "quasipoisson"), "nonnegative")
  invalid$design$variables$y <- NA_real_
  expect_error(fit_invented(invalid), "missing")
  expect_error(fit_invented(invalid, missing = "exclude"), "empty")
  expect_error(fit_invented(nis_domain(design, "domain", "fail"), y ~ 0), "finite|linear predictor|columns")
  saved <- options(survey.adjust.domain.lonely = TRUE)
  on.exit(options(saved), add = TRUE)
  before <- options()
  expect_error(fit_invented(design), "wr_unadjusted")
  expect_identical(options(), before)
})

test_that("frame and fitting warnings are retained once without escaping the model call", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  group <- factor(design$design$variables$group, levels = 0:2)
  stats::contrasts(group) <- stats::contr.treatment(levels(group))
  design$design$variables$group <- group
  before <- design
  expect_no_warning(fit <- fit_invented(design))
  expect_length(fit$diagnostics$warnings, 1L)
  expect_match(fit$diagnostics$warnings, "contrasts dropped")
  captured <- character()
  reference <- withCallingHandlers(survey::svyglm(y ~ x + group, design$design,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L)), warning = function(w) {
      captured <<- c(captured, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_identical(fit$diagnostics$warnings, unique(captured))
  expect_equal(stats::coef(fit$native), stats::coef(reference))
  expect_equal(stats::vcov(fit$native), stats::vcov(reference))
  expect_identical(fit$factors$group$levels, c("0", "1"))
  expect_identical(fit$native$contrasts$group, fit$factors$group$contrasts)
  expect_identical(design, before)
})

test_that("custom contrast preparation warnings survive fixed native coding", {
  session <- nis_open()
  on.exit(nis_close(session))
  contrast_name <- ".easynis_test_warning_contrasts"
  present <- exists(contrast_name, envir = .GlobalEnv, inherits = FALSE)
  previous <- if (present) get(contrast_name, envir = .GlobalEnv) else NULL
  assign(contrast_name, function(n, contrasts = TRUE) {
    warning("invented contrast preparation warning")
    stats::contr.sum(n, contrasts = contrasts)
  }, envir = .GlobalEnv)
  on.exit({
    if (present) assign(contrast_name, previous, envir = .GlobalEnv) else
      rm(list = contrast_name, envir = .GlobalEnv)
  }, add = TRUE)
  design <- model_design(session, model_fixture())
  design$design$variables$group <- factor(design$design$variables$group)
  attr(design$design$variables$group, "contrasts") <- contrast_name
  before <- design
  expect_no_warning(fit <- fit_invented(design))
  expect_identical(fit$diagnostics$warnings, "invented contrast preparation warning")
  captured <- character()
  reference <- withCallingHandlers(survey::svyglm(y ~ x + group, design$design,
    control = stats::glm.control(epsilon = 1e-10, maxit = 50L)), warning = function(w) {
      captured <<- c(captured, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_identical(fit$diagnostics$warnings, unique(captured))
  expect_equal(stats::coef(fit$native), stats::coef(reference))
  expect_equal(stats::vcov(fit$native), stats::vcov(reference))
  expect_identical(fit$factors$group$contrasts, stats::contr.sum(c("0", "1")))
  expect_identical(fit$native$contrasts$group, fit$factors$group$contrasts)
  expect_identical(design, before)
})
