test_that("compound domains preserve original PSU information and WR inference", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$AGE <- rep(c(10, 20, NA_real_), 4L)
  core$cohort <- core$HOSP_NIS %in% c("0001", "0003")
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022),
    c("AGE", "LOS", "cohort"), TRUE, "hospital_wr", "fail")
  before <- design
  options_before <- options()
  predicate <- ~ AGE >= 18 & cohort
  predicate_before <- predicate
  expect_error(nis_domain(design, predicate, "fail"), "unknown")
  selected <- nis_domain(design, predicate, "exclude")
  keep <- seq_len(nrow(core)) %in% c(2L, 8L)
  expected <- design$design[keep, ]
  expect_identical(selected$design, expected)
  expect_identical(selected$population, design$population)
  expect_identical(selected$provenance, design$provenance)
  expect_identical(selected$domains[[1L]], list(predicate = "AGE >= 18 & cohort",
    fields = c("AGE", "cohort"), missing = "exclude", supplied = 12L,
    included = 2L, excluded_false = 8L, unknown = 2L))
  expect_identical(selected$design$fpc$sampsize, expected$fpc$sampsize)
  weight <- core$DISCWT
  y <- core$LOS
  denominator <- sum(weight[keep])
  mean <- sum(weight[keep] * y[keep]) / denominator
  for (statistic in c("total", "mean")) {
    contribution <- numeric(nrow(core))
    contribution[keep] <- weight[keep] * if (statistic == "total") y[keep] else
      (y[keep] - mean) / denominator
    hospitals <- tapply(contribution, core$HOSP_NIS, sum)
    strata <- core$NIS_STRATUM[match(names(hospitals), core$HOSP_NIS)]
    variance <- sum(vapply(split(hospitals, strata), function(values) {
      length(values) / (length(values) - 1L) * sum((values - base::mean(values))^2)
    }, numeric(1)))
    result <- nis_estimate(selected, "LOS", statistic, "fail", 2, 0.95, "wr_unadjusted")
    expect_equal(result$estimate, if (statistic == "total") sum(weight[keep] * y[keep]) else mean,
      tolerance = 1e-12)
    expect_equal(result$se^2, variance, tolerance = 1e-12)
  }
  expect_identical(design, before)
  expect_identical(predicate, predicate_before)
  expect_identical(options(), options_before)
})

test_that("membership, missingness, raw sentinels and factor labels keep R meanings", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  rows <- design$design$variables
  rows$group <- factor(rep(c("Yes", "No", NA, "NA"), 16L), levels = c("Yes", "No", "NA"))
  rows$x[1L] <- -9
  rows[["quoted flag"]] <- rep(c(TRUE, FALSE), 32L)
  design$design$variables <- rows
  expressions <- list(~ (group == "Yes" | group == "No") & !is.na(x),
    ~ x %in% c(-9, 0, 1), ~ is.na(group), ~ group %in% c("Yes", NA),
    ~ `quoted flag` & !(x < 0), ~ group != "NA" & !is.na(group))
  expected <- list((rows$group == "Yes" | rows$group == "No") & !is.na(rows$x),
    rows$x %in% c(-9, 0, 1), is.na(rows$group), rows$group %in% c("Yes", NA),
    rows[["quoted flag"]] & !(rows$x < 0), rows$group != "NA" & !is.na(rows$group))
  for (i in seq_along(expressions)) {
    result <- nis_domain(design, expressions[[i]], "exclude")
    expect_identical(result$design$variables$KEY_NIS,
      rows$KEY_NIS[!is.na(expected[[i]]) & expected[[i]]])
    expect_identical(result$domains[[1L]]$unknown, sum(is.na(expected[[i]])))
  }
  expect_true(rows$KEY_NIS[1L] %in% nis_domain(design, ~ x == -9, "fail")$design$variables$KEY_NIS)
  expect_error(nis_domain(design, ~ group > "No", "exclude"), "evaluation warned")
})

test_that("pooled and repeated predicates retain year keys and empty domains", {
  session <- nis_open()
  on.exit(nis_close(session))
  rows <- model_fixture()
  second <- rows
  second$YEAR <- 2021L
  annual <- list(model_design(session, rows), model_design(session, second))
  pooled <- nis_pool_design(annual, c("x", "y", "domain"), "combined_total")
  selected <- nis_domain(pooled, ~ domain & x >= 0, "fail")
  keep <- pooled$design$variables$domain & pooled$design$variables$x >= 0
  expect_identical(selected$design, pooled$design[keep, ])
  expect_identical(selected$population, pooled$population)
  expect_length(unique(selected$design$cluster[[1L]]), 12L)
  estimate <- nis_estimate(selected, "y", "total", "fail", 12, 0.95, "wr_unadjusted")
  reference <- survey::svytotal(~ y, pooled$design[keep, ])
  expect_equal(estimate$estimate, unname(stats::coef(reference)), tolerance = 1e-12)
  expect_equal(estimate$se^2, unname(stats::vcov(reference))[1L], tolerance = 1e-10)
  empty <- nis_domain(selected, ~ x < -100, "fail")
  expect_equal(nrow(empty$design$variables), 0L)
  expect_length(empty$domains, 2L)
  expect_identical(empty$domains[[2L]]$supplied, sum(keep))
  expect_identical(empty$population, pooled$population)
  expect_equal(nrow(nis_domain(empty, ~ x > 0, "fail")$design$variables), 0L)
})

test_that("predicate evaluation cannot use globals, caller functions or sample-dependent forms", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  is.na <- function(...) stop("caller function must not run")
  cutoff <- 0
  predicate <- ~ !is.na(x) & x >= 0
  attr(predicate, "terms") <- stats::terms(~ stop("must not run"))
  result <- nis_domain(design, predicate, "fail")
  expect_identical(result$design$variables$x, design$design$variables$x[design$design$variables$x >= 0])
  expect_error(nis_domain(design, ~ x >= cutoff, "fail"), "global variables")
  unsafe <- list(~ mean(x) > 0, ~ x[1] > 0, ~ get("x") > 0, ~ base::is.na(x),
    ~ eval(x), ~ stop("must not run"), ~ x > stats::median(x), ~ (x <- 0),
    ~ x %in% y, ~ x >= c(0, 1), ~ is.na(x = x), y ~ x, ~ x && domain)
  for (formula in unsafe) {
    expect_error(nis_domain(design, formula, "fail"), "supported comparisons")
  }
  expect_error(nis_domain(design, ~ x & domain, "fail"), "numeric coding")
  expect_error(nis_domain(design, ~ !x, "fail"), "numeric coding")
  expect_error(nis_domain(design, ~ x, "fail"), "plain logical")
  expect_error(nis_domain(design, ~ TRUE, "fail"), "Every domain predicate field")
  design$design$variables$x[1L] <- Inf
  expect_error(nis_domain(design, ~ x > 0, "exclude"), "plain finite")
})

test_that("non-vector and custom-class fields cannot supply domain masks", {
  session <- nis_open()
  on.exit(nis_close(session))
  design <- model_design(session, model_fixture())
  rows <- design$design$variables
  invalid <- list(matrix(TRUE, nrow(rows), 1L),
    structure(rep(TRUE, nrow(rows)), class = "custom"), as.list(rows$x))
  for (value in invalid) {
    design$design$variables$bad <- value
    expect_error(nis_domain(design, ~ bad == TRUE, "fail"), "predicate fields")
    expect_error(nis_domain(design, "bad", "fail"), "plain logical")
  }
  design$design$variables$bad <- factor(rows$x)
  class(design$design$variables$bad) <- c("custom", "factor")
  expect_error(nis_domain(design, ~ bad == "0", "fail"), "predicate fields")
})
