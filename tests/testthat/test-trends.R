test_that("annual totals, pooled annualization and the year slope match survey", {
  years <- c(2017L, 2019L, 2020L)
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  path <- nis_example(years)
  withr::defer(unlink(path, recursive = TRUE))
  nis <- nis_open(path)
  con <- dbplyr::remote_con(nis)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  nis <- nis |>
    nis_flag_dx(heart_failure = "I50") |>
    dplyr::mutate(LOS = LOS + (YEAR - 2017L), DISCWT = DISCWT * (YEAR - 2016L))

  full <- nis |>
    dplyr::select(YEAR, HOSP_NIS, NIS_STRATUM, DISCWT, heart_failure, LOS) |>
    dplyr::collect() |>
    dplyr::mutate(
      psu = interaction(YEAR, HOSP_NIS),
      stratum = interaction(YEAR, NIS_STRATUM),
      in_cohort = as.integer(heart_failure),
      elapsed = YEAR - 2017L
    )
  reference <- survey::svydesign(~psu, strata = ~stratum, weights = ~DISCWT, data = full)

  annual <- nis_annual_totals(nis, heart_failure)
  yearly <- lapply(years, function(year) {
    survey::svytotal(~in_cohort, subset(reference, YEAR == year))
  })
  expect_identical(annual$YEAR, years)
  expect_equal(annual$discharges, vapply(yearly, function(x) as.numeric(coef(x)), numeric(1)), tolerance = 1e-8)
  expect_equal(
    annual$discharges_se,
    vapply(yearly, function(x) as.numeric(survey::SE(x)), numeric(1)),
    tolerance = 1e-8
  )

  pooled <- nis_design(nis, heart_failure, keep = LOS, annualize = TRUE)
  pooled_total <- srvyr::summarise(pooled, discharges = srvyr::survey_total())
  overall <- survey::svytotal(~in_cohort, reference)
  expect_equal(pooled_total$discharges, as.numeric(coef(overall)) / length(years), tolerance = 1e-8)
  expect_equal(pooled_total$discharges_se, as.numeric(survey::SE(overall)) / length(years), tolerance = 1e-8)

  design <- nis_design(nis, heart_failure, keep = LOS) |>
    dplyr::mutate(elapsed = YEAR - 2017L)
  fit <- survey::svyglm(LOS ~ elapsed, design)
  expected <- survey::svyglm(LOS ~ elapsed, subset(reference, heart_failure))
  expect_equal(coef(fit), coef(expected), tolerance = 1e-8)
  expect_equal(vcov(fit), vcov(expected), tolerance = 1e-8)

  expect_warning(
    sparse <- nis_annual_totals(nis, heart_failure & YEAR != 2019L),
    "No cohort discharges"
  )
  expect_identical(sparse$YEAR, years)
  expect_equal(sparse$discharges, replace(annual$discharges, 2, NA_real_))
  expect_equal(sparse$discharges_se, replace(annual$discharges_se, 2, NA_real_))
})

test_that("annual totals check the design and ICD boundaries before applying the cohort", {
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  path <- nis_example(c(2012L, 2015:2016))
  withr::defer(unlink(path, recursive = TRUE))
  nis <- nis_open(path)
  con <- dbplyr::remote_con(nis)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  icd9 <- dplyr::filter(nis, YEAR == 2012L)
  expect_identical(nis_annual_totals(icd9, TRUE)$YEAR, 2012L)
  double_quarters <- dplyr::mutate(icd9, DQTR = as.double(DQTR))
  expect_identical(nis_annual_totals(double_quarters, TRUE)$YEAR, 2012L)
  expect_error(nis_annual_totals(dplyr::mutate(icd9, YEAR = 2011L), TRUE), "2012")
  expect_error(nis_annual_totals(nis, YEAR >= 2016L), "2015")
  expect_error(nis_annual_totals(dplyr::filter(nis, YEAR != 2015L), TRUE), "ICD-9.*ICD-10")
  expect_identical(nis_annual_totals(nis, AGE >= 18, coding = "independent")$YEAR, c(2012L, 2015:2016))
  expect_error(
    nis_annual_totals(dplyr::filter(nis, YEAR == 2015L, DQTR == 4L), TRUE, coding = "independent"),
    "quarter"
  )
  expect_error(nis_annual_totals(dplyr::select(icd9, -DQTR), TRUE), "DQTR")
})
