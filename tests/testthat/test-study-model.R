coef.study_fit_test <- function(object, ...) c(`(Intercept)` = 1, exposed = 0.5)
vcov.study_fit_test <- function(object, ...) diag(2)
coef.study_bad_coef <- function(object, ...) c(`(Intercept)` = NA_real_)
vcov.study_bad_coef <- function(object, ...) matrix(1)
coef.study_bad_vcov <- function(object, ...) c(`(Intercept)` = 1)
vcov.study_bad_vcov <- function(object, ...) matrix(Inf)
registerS3method("coef", "study_fit_test", coef.study_fit_test,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_fit_test", vcov.study_fit_test,
                 envir = asNamespace("stats"))
registerS3method("coef", "study_bad_coef", coef.study_bad_coef,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_bad_coef", vcov.study_bad_coef,
                 envir = asNamespace("stats"))
registerS3method("coef", "study_bad_vcov", coef.study_bad_vcov,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_bad_vcov", vcov.study_bad_vcov,
                 envir = asNamespace("stats"))

test_that("internal helpers: model fitting reports successful, failed, and unstable fits", {
  fit_model <- getFromNamespace("nis_study_fit_model", "easyNIS")
  design <- list(variables = data.frame(
    y = c(0, 1, 0, 1), exposed = c(0, 1, 0, 1), x = c(1, 2, 2, 1)
  ))
  formula <- y ~ exposed + x
  fitted <- structure(list(converged = TRUE), class = "study_fit_test")
  fit_ok <- function(...) fitted

  success <- fit_model(formula, design, stats::gaussian(), fit = fit_ok,
                       outcome = "y", exposure = "exposed")
  expect_identical(success$model, fitted)
  expect_null(success$status)
  expect_identical(success$warnings, character())

  fit_error <- function(...) stop("synthetic fit failure")
  failed <- fit_model(formula, design, stats::gaussian(), fit = fit_error)
  expect_null(failed$model)
  expect_identical(failed$status, "Model fit failed: synthetic fit failure")
  expect_identical(failed$warnings, character())

  not_converged <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    structure(list(converged = FALSE), class = "study_fit_test")
  })
  expect_null(not_converged$model)
  expect_identical(not_converged$status, "The model did not converge.")

  benign <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    warning("synthetic benign warning")
    fitted
  })
  expect_identical(benign$model, fitted)
  expect_null(benign$status)
  expect_identical(benign$warnings, "synthetic benign warning")

  material <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    warning("synthetic fit did not converge")
    fitted
  })
  expect_null(material$model)
  expect_match(material$status, "model fit is unstable")
  expect_identical(material$warnings, "synthetic fit did not converge")
})

test_that("internal helpers: model fitting rejects invalid estimates", {
  fit_model <- getFromNamespace("nis_study_fit_model", "easyNIS")
  design <- list(variables = data.frame(y = 0:3, exposed = c(0, 1, 0, 1)))
  formula <- y ~ exposed
  expect_error_methods <- function(model, expected) {
    result <- fit_model(formula, design, stats::gaussian(), fit = function(...) model)
    expect_null(result$model)
    expect_identical(result$status, expected)
    expect_identical(result$warnings, character())
  }
  expect_error_methods(structure(list(converged = TRUE, bad = "coef"),
                                class = "study_bad_coef"),
                       "The model returned missing or non-finite coefficients.")
  expect_error_methods(structure(list(converged = TRUE, bad = "vcov"),
                                class = "study_bad_vcov"),
                       "The model returned missing or non-finite covariance estimates.")
})

test_that("internal helpers: model formula preflight handles complete cases and invalid specifications", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  valid <- data.frame(y = c(0, 1, 0, NA), exposed = c(0, 1, 0, 1), x = c(1, 2, 3, 4))
  expect_null(model_status(valid, "y", "exposed", y ~ exposed + x))

  expect_match(model_status(valid, "y", "exposed", y ~ absent), "fails on complete-case rows")
  no_complete_cases <- data.frame(y = c(0, 1), exposed = c(0, 1), x = c(NA, NA))
  expect_match(model_status(no_complete_cases, "y", "exposed", y ~ exposed + x),
               "no complete-case rows")

  # Inject a QR failure to exercise the otherwise difficult rank-evaluation boundary.
  testthat::local_mocked_bindings(
    qr = function(...) stop("synthetic QR failure"), .package = "base"
  )
  expect_match(model_status(valid, "y", "exposed", y ~ exposed + x),
               "rank could not be evaluated")
})

test_that("internal helpers: model preflight describes missing data and non-finite values", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  expect_match(model_status(NULL, "y", "exposed"), "unavailable")
  expect_match(model_status(data.frame(y = 0:1), "y", "exposed"), "missing exposed")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, Inf)),
                            "y", "exposed", y ~ exposed), "non-finite")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, Inf)),
                            "y", "exposed"), "exposure exposed contains non-finite")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, 1),
                                       x = c(Inf, 1)), "y", "exposed", y ~ exposed + x),
               "non-finite values on complete-case rows")
})

test_that("study model preflight describes empty, sparse, and unstable inputs", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  expect_match(model_status(data.frame(), "outcome", "exposed"), "no rows")
  expect_match(
    model_status(data.frame(outcome = 0:2, exposed = FALSE), "outcome", "exposed"),
    "fewer than two observed levels"
  )
  expect_match(
    model_status(data.frame(outcome = 1, exposed = c(FALSE, TRUE)), "outcome", "exposed"),
    "fewer than two observed values"
  )
  expect_match(
    model_status(data.frame(outcome = c(0, 1), exposed = c(FALSE, TRUE), x = c(1, Inf)),
                 "outcome", "exposed", outcome ~ exposed + x),
    "non-finite values on complete-case rows"
  )
  expect_match(
    model_status(data.frame(outcome = c(0, 1, 0, 1), exposed = c(FALSE, TRUE, FALSE, TRUE),
                            x = c(1, 2, 1, 2)),
                 "outcome", "exposed", outcome ~ exposed + x),
    "rank-deficient"
  )
  expect_null(model_status(
    data.frame(outcome = c(0, 1, NA), exposed = c(FALSE, TRUE, TRUE)),
    "outcome", "exposed"
  ))
})

test_that("study model preflight uses the factor levels present in complete cases", {
  frame <- expand.grid(YEAR = 2018:2020, exposed = c(FALSE, TRUE), replicate = 1:8)
  frame$y <- as.numeric((frame$replicate + as.integer(frame$exposed)) %% 3L == 0L)
  frame$y[frame$YEAR == 2020L] <- NA_real_
  frame$weight <- 1
  design <- survey::svydesign(ids = ~1, weights = ~weight, data = frame)
  formula <- y ~ exposed + factor(YEAR)
  expected <- survey::svyglm(formula, design, family = stats::quasibinomial())
  actual <- nis_study_fit_model(formula, design, stats::quasibinomial(),
    outcome = "y", exposure = "exposed")
  expect_null(actual$status)
  expect_equal(stats::coef(actual$model), stats::coef(expected))
})
