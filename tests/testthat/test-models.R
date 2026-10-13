test_that("shared predictors preserve mixed-family fits and separate analysis samples", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$y[rows$HOSP_NIS == "0004"] <- NA
  rows$binary[rows$HOSP_NIS == "0003"] <- NA
  rows$binary[1L] <- NA
  rows$count[c(1L, 17L)] <- NA
  rows$x[rows$HOSP_NIS == "0008"] <- NA
  design <- model_design(session, rows)
  before <- design
  options_before <- options()[grepl("^survey[.]|^contrasts$|^na.action$", names(options()))]
  outcomes <- c(y = "gaussian", binary = "quasibinomial", count = "quasipoisson")
  predictors <- ~ x + group
  formula_before <- predictors
  for (domain in c(FALSE, TRUE)) {
    selected <- if (domain) nis_domain(design, "domain", "fail") else design
    batch <- nis_models(selected, outcomes, predictors, "exclude", 6, 0.9, "wr_unadjusted")
    expect_s3_class(batch, "nis_models")
    expect_identical(names(batch$models), names(outcomes))
    expect_identical(batch$sample$outcome, names(outcomes))
    expect_identical(batch$sample$family, unname(outcomes))
    expect_false(batch$provenance$analysis_ready)
    expect_identical(batch$provenance$disclosure_status, "unreviewed")
    expect_identical(batch$provenance$interval_scope, "pointwise")
    expect_identical(batch$provenance$multiplicity_adjustment, "none")
    expect_length(unique(batch$sample$raw_included), 3L)
    supplied <- if (domain) rows$domain else rep(TRUE, nrow(rows))
    for (i in seq_along(outcomes)) {
      field <- names(outcomes)[i]
      formula <- stats::reformulate(c("x", "group"), field)
      direct <- nis_model(selected, formula, outcomes[[i]], "exclude", 6, 0.9, "wr_unadjusted")
      result <- batch$models[[i]]
      keep <- supplied & !is.na(rows[[field]]) & !is.na(rows$x)
      family <- switch(outcomes[[i]], gaussian = stats::gaussian(),
        quasibinomial = stats::quasibinomial(), quasipoisson = stats::quasipoisson())
      reference <- model_sandwich(rows, formula, family, keep)
      tolerance <- if (outcomes[[i]] == "gaussian") 1e-10 else 1e-7
      expect_equal(stats::coef(result$native), reference$coefficients, tolerance = 1e-8)
      expect_lt(max(abs(stats::vcov(result$native) - reference$covariance)), tolerance)
      expect_identical(result$coefficients, direct$coefficients)
      expect_identical(stats::vcov(result$native), stats::vcov(direct$native))
      expect_identical(result$sample, direct$sample)
      expect_identical(result$diagnostics, direct$diagnostics)
      expect_identical(result$provenance, direct$provenance)
      expect_identical(batch$sample$raw_supplied[i], as.double(sum(supplied)))
      expect_identical(batch$sample$raw_included[i], as.double(sum(keep)))
      expect_identical(batch$sample$raw_missing[i], as.double(sum(supplied & !keep)))
      expect_equal(batch$sample$weighted_denominator[i], sum(rows$DISCWT[keep]))
    }
  }
  expect_identical(design, before)
  expect_identical(predictors, formula_before)
  expect_identical(options()[names(options_before)], options_before)
})

test_that("batches retain pooled year keys and pooling-divisor invariance", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  second <- rows
  second$YEAR <- 2021L
  second$DISCWT <- second$DISCWT * 2
  second$y <- second$y + 0.5
  annual <- list(model_design(session, rows), model_design(session, second))
  columns <- c("y", "binary", "x", "group", "domain")
  combined <- nis_pool_design(annual, columns, "combined_total")
  average <- nis_pool_design(annual, columns, "average_annual_total")
  outcomes <- c(binary = "quasibinomial", y = "gaussian")
  combined_batch <- nis_models(combined, outcomes, ~ x + group, "fail", 12, 0.95, "wr_unadjusted")
  average_batch <- nis_models(average, outcomes, ~ x + group, "fail", 12, 0.95, "wr_unadjusted")
  for (field in names(outcomes)) {
    expect_equal(combined_batch$models[[field]]$coefficients,
      average_batch$models[[field]]$coefficients, tolerance = 1e-12)
    expect_identical(combined_batch$models[[field]]$sample$full_population_degrees_of_freedom, 12L)
    expect_length(unique(combined_batch$models[[field]]$design$cluster[[1L]]), 16L)
  }
  expect_equal(combined_batch$sample$weighted_denominator,
    2 * average_batch$sample$weighted_denominator)
  reference_rows <- rbind(rows, second)
  reference <- model_sandwich(reference_rows, y ~ x + group, stats::gaussian(),
    rep(TRUE, nrow(reference_rows)))
  expect_equal(stats::coef(combined_batch$models$y$native), reference$coefficients, tolerance = 1e-10)
  expect_lt(max(abs(stats::vcov(combined_batch$models$y$native) - reference$covariance)), 1e-10)
})

test_that("literal outcome names and formula restrictions survive batch construction", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  field <- "stay; stop('must not run')"
  design$design$variables[[field]] <- design$design$variables$y
  outcomes <- stats::setNames("gaussian", field)
  predictors <- ~ x + I(group)
  attr(predictors, "terms") <- stats::terms(~ x)
  batch <- nis_models(design, outcomes, predictors, "fail", Inf, 0.95, "wr_unadjusted")
  direct <- nis_model(design, y ~ x + I(group), "gaussian", "fail", Inf, 0.95, "wr_unadjusted")
  expect_identical(names(batch$models), field)
  expect_identical(batch$sample$outcome, field)
  expect_equal(batch$models[[field]]$coefficients, direct$coefficients, tolerance = 0)
  expect_identical(batch$models[[field]]$provenance$response_fields, field)
  error <- tryCatch(nis_models(design, c(y = "gaussian"), ~ stop("must not run"),
    "fail", 6, 0.95, "wr_unadjusted"), error = identity)
  expect_s3_class(error, "nis_models_error")
  expect_match(conditionMessage(error$parent), "supported row-wise terms")
  expect_error(nis_models(design, c(y = "gaussian"), ~ ., "fail", 6, 0.95, "wr_unadjusted"),
    "dot expansion")
})

test_that("batch failures identify the outcome and never expose partial fits", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$binary[1L] <- NA
  design <- model_design(session, rows)
  before <- design
  error <- tryCatch(nis_models(design, c(y = "gaussian", binary = "quasibinomial"),
    ~ x, "fail", 6, 0.95, "wr_unadjusted"), error = identity)
  expect_s3_class(error, "nis_models_error")
  expect_identical(error$outcome, "binary")
  expect_s3_class(error$parent, "error")
  expect_match(conditionMessage(error), "binary.*missing")
  expect_false(any(c("models", "results", "sample") %in% names(error)))
  expect_identical(design, before)
  expect_error(nis_models(design, c(y = "gaussian", unknown = "gaussian"),
    ~ x, "exclude", 6, 0.95, "wr_unadjusted"), "unknown.*retained")
  policies <- options(survey.lonely.psu = "adjust")
  on.exit(options(policies), add = TRUE)
  expect_error(nis_models(design, c(y = "gaussian"), ~ 1,
    "fail", 6, 0.95, "wr_unadjusted"), "wr_unadjusted requires")
})

test_that("batch declarations require exact names, families and explicit inference", {
  invalid <- list(character(), "gaussian", c(y = "unknown"), c(y = NA_character_),
    stats::setNames("gaussian", ""), stats::setNames("gaussian", "  "),
    stats::setNames("gaussian", NA_character_), c(y = "gaussian", y = "gaussian"),
    list(y = "gaussian"), factor(c(y = "gaussian")),
    structure(c(y = "gaussian"), class = "custom"), matrix("gaussian", 1L, 1L))
  for (outcomes in invalid) {
    expect_error(nis_models(NULL, outcomes, ~ 1, "fail", 6, 0.95, "wr_unadjusted"), "outcomes")
  }
  for (predictors in list("~ x", y ~ x, quote(x), NULL)) {
    expect_error(nis_models(NULL, c(y = "gaussian"), predictors,
      "fail", 6, 0.95, "wr_unadjusted"), "one-sided formula")
  }
  expect_error(nis_models(NULL, c(y = "gaussian"), ~ 1), "explicit")
  expect_error(nis_models(NULL, c(y = "gaussian"), ~ 1, "fail", 6, 0.95), "explicit")
})

test_that("aliases, factor coding and nonconvergence stay visible per outcome", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  rows$group <- rows$x
  design <- model_design(session, rows)
  aliased <- nis_models(design, c(y = "gaussian", binary = "quasibinomial"),
    ~ x + group, "fail", 6, 0.95, "wr_unadjusted")
  expect_true(all(vapply(aliased$models, function(model) "group" %in% model$diagnostics$aliased, logical(1))))
  expect_true(all(vapply(aliased$models, function(model) is.na(model$coefficients$estimate[3L]), logical(1))))
  design <- model_design(session, model_fixture())
  design$design$variables$group <- factor(design$design$variables$group,
    levels = c(1, 0), labels = c("treated", "reference"))
  factors <- nis_models(design, c(y = "gaussian", binary = "quasibinomial"),
    ~ x * group, "fail", Inf, 0.9, "wr_unadjusted")
  for (model in factors$models) {
    expect_identical(model$factors$group$levels, c("treated", "reference"))
    expect_identical(model$factors$group$zero_coded_levels, "treated")
    expect_true("x:groupreference" %in% model$coefficients$term)
  }
  design$design$variables$count <- ifelse(design$design$variables$x > 0, 1e60, 0)
  warnings <- nis_models(design, c(y = "gaussian", count = "quasipoisson"),
    ~ x, "fail", 6, 0.95, "wr_unadjusted")
  expect_true(warnings$models$y$diagnostics$converged)
  expect_false(warnings$models$count$diagnostics$converged)
  expect_true(any(grepl("did not converge", warnings$models$count$diagnostics$warnings)))
  expect_false(warnings$provenance$analysis_ready)
})
