test_that("nis_design placeholder designs match full-data domain estimates", {
  designs <- comparison_designs()
  on.exit(unlink(designs$path, recursive = TRUE), add = TRUE)

  old_lonely <- getOption("survey.lonely.psu")
  old_adjust <- getOption("survey.adjust.domain.lonely")
  on.exit(options(
    survey.lonely.psu = old_lonely,
    survey.adjust.domain.lonely = old_adjust
  ), add = TRUE)

  settings <- list(
    adjusted = list(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE),
    default = list(survey.lonely.psu = NULL, survey.adjust.domain.lonely = NULL)
  )

  for (setting in settings) {
    do.call(options, setting)
    full <- designs$full
    placeholder <- designs$placeholder

    mean_full <- survey::svymean(~AGE + LOS, full)
    mean_placeholder <- survey::svymean(~AGE + LOS, placeholder)
    expect_equal(coef(mean_placeholder), coef(mean_full), tolerance = 1e-8)
    expect_equal(survey::SE(mean_placeholder), survey::SE(mean_full), tolerance = 1e-8)

    total_full <- survey::svytotal(~AGE + LOS, full)
    total_placeholder <- survey::svytotal(~AGE + LOS, placeholder)
    expect_equal(coef(total_placeholder), coef(total_full), tolerance = 1e-8)
    expect_equal(survey::SE(total_placeholder), survey::SE(total_full), tolerance = 1e-8)

    by_full <- survey::svyby(~AGE, ~FEMALE, full, survey::svymean, vartype = "se")
    by_placeholder <- survey::svyby(
      ~AGE, ~FEMALE, placeholder, survey::svymean, vartype = "se"
    )
    expect_equal(coef(by_placeholder), coef(by_full), tolerance = 1e-8)
    expect_equal(survey::SE(by_placeholder), survey::SE(by_full), tolerance = 1e-8)

    logistic_full <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = full,
      family = stats::quasibinomial()
    )
    logistic_placeholder <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = placeholder,
      family = stats::quasibinomial()
    )
    expect_equal(coef(logistic_placeholder), coef(logistic_full), tolerance = 1e-8)
    expect_equal(vcov(logistic_placeholder), vcov(logistic_full), tolerance = 1e-8)

    gaussian_full <- survey::svyglm(
      AGE ~ LOS + DIED + factor(YEAR), design = full, family = stats::gaussian()
    )
    gaussian_placeholder <- survey::svyglm(
      AGE ~ LOS + DIED + factor(YEAR),
      design = placeholder,
      family = stats::gaussian()
    )
    expect_equal(coef(gaussian_placeholder), coef(gaussian_full), tolerance = 1e-8)
    expect_equal(vcov(gaussian_placeholder), vcov(gaussian_full), tolerance = 1e-8)

    quantile_full <- survey::svyquantile(~AGE, full, quantiles = 0.5, ci = FALSE)
    quantile_placeholder <- survey::svyquantile(
      ~AGE, placeholder, quantiles = 0.5, ci = FALSE
    )
    expect_equal(coef(quantile_placeholder), coef(quantile_full), tolerance = 1e-8)
    expect_equal(survey::degf(placeholder), survey::degf(full))

    table_full <- gtsummary::tbl_svysummary(
      full,
      by = FEMALE,
      include = c(AGE, LOS),
      statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
    ) |>
      gtsummary::add_p()
    table_placeholder <- gtsummary::tbl_svysummary(
      placeholder,
      by = FEMALE,
      include = c(AGE, LOS),
      statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
    ) |>
      gtsummary::add_p()
    expect_equal(
      table_placeholder$table_body$p.value,
      table_full$table_body$p.value,
      tolerance = 1e-8
    )
  }
})

test_that("annualized weights divide by the number of years and missing cohorts are excluded", {
  path <- nis_example(2017:2019)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  annualized <- nis_design(
    query,
    heart_failure,
    keep = c(AGE),
    annualize = TRUE
  )
  expected_weights <- query |>
    dplyr::filter(heart_failure) |>
    dplyr::select(DISCWT) |>
    dplyr::collect() |>
    dplyr::pull(DISCWT) / 3
  expect_equal(as.numeric(stats::weights(annualized)), expected_weights)

  data <- dplyr::tibble(
    YEAR = c(2017, 2017), HOSP_NIS = 1:2, NIS_STRATUM = c(1, 1),
    DISCWT = c(1, 1), AGE = c(50, 60), eligible = c(TRUE, NA)
  )
  expect_message(
    domain <- nis_design(data, eligible, keep = c(AGE)),
    "1 missing cohort value"
  )
  expect_equal(nrow(domain$variables), 1L)
})

test_that("placeholder rows keep design fields and tolerate all-NA analysis values", {
  data <- dplyr::tibble(
    YEAR = c(2017, 2017),
    HOSP_NIS = c(1, 2),
    NIS_STRATUM = c(1, 1),
    DISCWT = c(1, 1),
    eligible = c(TRUE, FALSE),
    DIED = c(1, NA_real_),
    TOTCHG = c(1000, NA_real_),
    CCR_NIS = c(0.25, NA_real_)
  )

  design <- nis_design(
    data,
    eligible,
    keep = c(DIED, TOTCHG, CCR_NIS),
    dollars = 2022
  )

  expect_equal(nrow(design$variables), 1L)
  expect_identical(as.character(design$variables$DIED), "Yes")
  expect_true(is.finite(design$variables$cost_adj[[1L]]))
  expect_equal(as.numeric(design$variables$YEAR), 2017)
  expect_equal(as.numeric(design$variables$HOSP_NIS), 1)
  expect_equal(as.numeric(design$variables$NIS_STRATUM), 1)
  expect_equal(as.numeric(design$variables$DISCWT), 1)

  placeholder <- dplyr::tibble(
    YEAR = 2017,
    HOSP_NIS = 2,
    NIS_STRATUM = 1,
    DISCWT = 1,
    DIED = NA_real_,
    TOTCHG = NA_real_,
    CCR_NIS = NA_real_
  ) |>
    nis_label()
  adjusted_placeholder <- nis_cost(placeholder, dollars = 2022)
  expect_true(is.na(adjusted_placeholder$DIED[[1L]]))
  expect_true(is.na(adjusted_placeholder$cost_adj[[1L]]))
})
