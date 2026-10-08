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
    c("y", "binary", "count", "x", "group", "domain"), TRUE, "hospital_wr", "fail")
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

test_that("invalid formulas, fields and policies fail without caller mutation", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  expect_error(nis_model(design, y ~ x), "explicit")
  for (formula in list(~ x, log(y) ~ x, y ~ log(x), y ~ offset(x), y ~ ., y ~ I(x^2),
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
