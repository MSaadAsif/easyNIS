reweight_fixture <- function(cohort = "partial") {
  data <- expand.grid(discharge = 1:3, hospital = 1:6, YEAR = 2019:2020)
  data$HOSP_NIS <- data$hospital
  data$NIS_STRATUM <- ceiling(data$hospital / 3)
  data$DISCWT <- 2 + seq_len(nrow(data)) / 10
  data$AGE <- 20 + seq_len(nrow(data)) %% 6 * 10
  data$eligible <- switch(
    cohort,
    partial = data$hospital %% 3 != 0 & data$discharge != 3,
    all = rep(TRUE, nrow(data)),
    empty = rep(FALSE, nrow(data))
  )
  data$psu <- paste(data$YEAR, data$HOSP_NIS, sep = "::")
  data$stratum <- paste(data$YEAR, data$NIS_STRATUM, sep = "::")
  data$weight <- data$DISCWT / 2
  data
}

reweight_reference <- function(data, multipliers) {
  data$weight[data$eligible] <- data$weight[data$eligible] * multipliers
  reference <- survey::svydesign(~psu, strata = ~stratum, weights = ~weight, data = data, nest = TRUE)
  reference[data$eligible, ]
}

expect_reweight_estimates <- function(actual, reference, formula) {
  for (estimator in list(survey::svymean, survey::svytotal)) {
    observed <- estimator(formula, actual)
    expected <- estimator(formula, reference)
    testthat::expect_equal(coef(observed), coef(expected), tolerance = 1e-10)
    testthat::expect_equal(survey::SE(observed), survey::SE(expected), tolerance = 1e-10)
  }
  testthat::expect_equal(survey::degf(actual), survey::degf(reference))
}

test_that("reweight restores selected design fields from intact survey metadata", {
  data <- reweight_fixture()
  design <- nis_design(data, eligible, keep = AGE, annualize = TRUE)
  selected <- dplyr::select(design, AGE)
  attr(selected, "nis_cost_provenance") <- list(dollars = 2020, charges = "invented")
  for (multipliers in list(rep(1, sum(data$eligible)), rep(c(0.5, 1.2, 2, 0.8), length.out = sum(data$eligible)))) {
    actual <- nis_reweight(selected, multipliers)
    reference <- reweight_reference(data, multipliers)
    expect_reweight_estimates(actual, reference, ~AGE)
    expect_identical(actual$cluster[[1L]], design$cluster[[1L]])
    expect_identical(actual$strata[[1L]], design$strata[[1L]])
    expect_identical(actual$fpc, design$fpc)
    expect_equal(as.numeric(stats::weights(actual)),
      as.numeric(stats::weights(selected)) * multipliers)
    expect_identical(names(actual$variables), "AGE")
    expect_identical(attr(actual$variables$AGE, "label"), attr(selected$variables$AGE, "label"))
    expect_identical(attr(actual, "nis_excluded"), attr(selected, "nis_excluded"))
    expect_identical(attr(actual, "nis_cost_provenance"), attr(selected, "nis_cost_provenance"))
    expect_identical(attr(actual, "nis_placeholder_rows")$.nis_weight, attr(design, "nis_placeholder_rows")$.nis_weight)
    expect_equal(
      as.numeric(stats::weights(nis_reweight(actual, multipliers))),
      as.numeric(stats::weights(selected)) * multipliers^2
    )
  }
})

test_that("factor mutations, renames and new columns retain the current schema", {
  data <- reweight_fixture()
  design <- nis_design(data, eligible, keep = AGE, annualize = TRUE)
  multipliers <- rep(c(0.5, 1.2, 2, 0.8), length.out = sum(data$eligible))
  reference <- reweight_reference(data, multipliers)
  reference$variables$age_group <- factor(
    reference$variables$AGE,
    levels = c(70, 60, 50, 40, 30, 20, 99),
    ordered = TRUE
  )
  reference$variables$new_age <- reference$variables$AGE + 5
  transformed <- design |>
    dplyr::mutate(
      AGE = factor(AGE, levels = c(70, 60, 50, 40, 30, 20, 99), ordered = TRUE),
      new_age = as.numeric(as.character(AGE)) + 5,
      iptw = multipliers
    ) |>
    dplyr::rename(age_group = AGE) |>
    dplyr::select(age_group, new_age, iptw)
  actual <- nis_reweight(transformed, iptw)
  expect_reweight_estimates(
    nis_reweight(transformed, rep(1, nrow(transformed$variables))),
    transformed,
    ~ age_group + new_age
  )
  expect_reweight_estimates(actual, reference, ~ age_group + new_age)
  expect_identical(actual$variables$age_group, transformed$variables$age_group)
  placeholders <- attr(actual, "nis_placeholder_rows")
  expect_identical(placeholders, attr(design, "nis_placeholder_rows"))
  expect_false(any(c("AGE", "YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT") %in% names(actual$variables)))

  mutated <- dplyr::mutate(design, AGE = factor(AGE), YEAR = "analysis year", HOSP_NIS = factor(HOSP_NIS))
  result <- nis_reweight(mutated, multipliers)
  factor_reference <- reweight_reference(data, multipliers)
  factor_reference$variables$AGE <- factor(factor_reference$variables$AGE)
  expect_reweight_estimates(result, factor_reference, ~AGE)
  expect_identical(result$variables$YEAR, mutated$variables$YEAR)
  expect_identical(result$variables$HOSP_NIS, mutated$variables$HOSP_NIS)
})

test_that("reweight handles no placeholders and an empty cohort", {
  for (cohort in c("all", "empty")) {
    data <- reweight_fixture(cohort)
    design <- suppressWarnings(nis_design(data, eligible, keep = AGE, annualize = TRUE))
    design <- dplyr::select(design, AGE) |>
      dplyr::mutate(AGE = factor(AGE, levels = seq(20, 70, 10)))
    multipliers <- rep(1.5, sum(data$eligible))
    actual <- nis_reweight(design, multipliers)
    reference <- reweight_reference(data, multipliers)
    reference$variables$AGE <- factor(reference$variables$AGE, levels = seq(20, 70, 10))
    expect_reweight_estimates(actual, reference, ~AGE)
    expect_equal(nrow(actual$variables), sum(data$eligible))
    expect_equal(nrow(attr(actual, "nis_placeholder_rows")), nrow(attr(design, "nis_placeholder_rows")))
    expect_identical(actual$cluster[[1L]], design$cluster[[1L]])
    expect_identical(actual$strata[[1L]], design$strata[[1L]])
  }
})

test_that("a filter that retains every cohort row permits reweighting", {
  data <- reweight_fixture("all")
  data$DISCWT <- seq_len(nrow(data))
  outside <- dplyr::mutate(data[1L, ], HOSP_NIS = 7L, NIS_STRATUM = 3L, eligible = FALSE)
  whole <- nis_design(data, eligible, keep = AGE)
  domain <- nis_design(dplyr::bind_rows(data, outside), eligible, keep = AGE)
  factors <- rep(c(0.5, 1.2), length.out = nrow(data))

  actual <- nis_reweight(dplyr::filter(whole, !is.na(AGE)), factors)
  expected <- nis_reweight(domain, factors)
  expect_reweight_estimates(actual, expected, ~AGE)
  expect_identical(stats::weights(actual), stats::weights(expected))
  expect_type(whole$variables$DISCWT, "double")
  expect_identical(whole$variables$DISCWT, domain$variables$DISCWT)
})

test_that("reweight rejects narrowed or unsupported survey structures", {
  data <- reweight_fixture()
  design <- nis_design(data, eligible, keep = AGE, annualize = TRUE)
  narrowed <- dplyr::select(design, AGE) |>
    dplyr::filter(AGE > 30)
  expect_error(nis_reweight(narrowed, rep(1, nrow(narrowed$variables))), "narrowed")
  unsupported <- design
  unsupported$fpc$popsize <- matrix(1000, nrow(design$variables), 1)
  expect_error(nis_reweight(unsupported, rep(1, nrow(design$variables))), "unsupported survey structure")
  unsupported <- design
  unsupported$fpc$sampsize[,] <- 1000L
  expect_error(nis_reweight(unsupported, rep(1, nrow(design$variables))), "cannot be safely rebuilt")
})


test_that("integer64 discharge weights and factors retain a numeric survey design", {
  skip_if_not_installed("bit64")
  frame <- dplyr::tibble(
    YEAR = 2020L,
    HOSP_NIS = rep(1:4, each = 2L),
    NIS_STRATUM = 1L,
    DISCWT = c(2, 3, 2, 3, 2, 3, 2, 3),
    eligible = HOSP_NIS < 4L
  )
  weighted <- dplyr::mutate(frame, DISCWT = bit64::as.integer64(DISCWT))
  baseline <- nis_design(frame, eligible, keep = YEAR)
  design <- nis_design(weighted, eligible, keep = YEAR)
  factor <- bit64::as.integer64(2:7)
  actual <- nis_reweight(design, factor)
  expected <- nis_reweight(baseline, 2:7)
  expect_equal(unname(stats::weights(actual)), unname(stats::weights(expected)))
  expect_error(nis_reweight(design, rep(.Machine$double.xmax, 6L)), "finite weights")
  expect_error(nis_reweight(design, rep(1e-310, 6L)), "finite weights")
})
