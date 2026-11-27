test_that("lazy Taylor summaries retain the sampled PSUs through domain and missingness", {
  withr::local_options(list(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE))
  withr::local_options(list(easyNIS.duckdb_config = list(threads = 2L)))
  query <- suppressWarnings(nis_open(nis_example(2019:2020))) |>
    dplyr::mutate(
      female_flag = FEMALE == 1L,
      los_days = ifelse(HOSP_NIS == 2L, NA_real_, LOS),
      shifted = 1e12 + los_days,
      cents = dbplyr::sql("CAST(AGE AS DECIMAL(18, 12))")
    )
  reference <- lazy_reference(query)
  local_mocked_bindings(nis_collect = function(...) stop("Unexpected discharge collection"))
  design <- nis_survey(query)
  expect_lazy_stat(
    survey::svytotal(~ los_days + female_flag, design, na.rm = TRUE),
    survey::svytotal(~ los_days + female_flag, reference, na.rm = TRUE)
  )
  expect_lazy_stat(survey::svymean(~los_days, design), survey::svymean(~los_days, reference))
  expect_lazy_stat(survey::svytotal(~ los_days + AGE, design), survey::svytotal(~ los_days + AGE, reference))
  expect_lazy_stat(survey::svymean(~ los_days + AGE, design), survey::svymean(~ los_days + AGE, reference))
  expect_lazy_stat(
    survey::svymean(~los_days, subset(design, FALSE)),
    survey::svymean(~los_days, subset(reference, FALSE))
  )
  expect_lazy_stat(
    survey::svymean(~los_days, subset(design, HOSP_NIS == 2L), na.rm = TRUE),
    survey::svymean(~los_days, subset(reference, HOSP_NIS == 2L), na.rm = TRUE)
  )
  expect_lazy_stat(survey::svymean(~ I(cents * cents), design), survey::svymean(~ I(cents * cents), reference))
  domain <- dplyr::filter(subset(design, AGE >= 50), HOSP_NIS %% 4L == 1L)
  ref_domain <- subset(reference, AGE >= 50 & HOSP_NIS %% 4L == 1L)
  expect_lazy_stat(survey::svymean(~los_days, domain), survey::svymean(~los_days, ref_domain))
  expect_equal(
    as.numeric(survey::SE(survey::svymean(~shifted, domain))),
    as.numeric(survey::SE(survey::svymean(~los_days, ref_domain))),
    tolerance = 1e-8
  )

  expect_error(survey::svyquantile(~LOS, design, 0.5), "nis_design")
  expect_error(survey::svychisq(~ RACE + PAY1, design), "nis_design")
  if (requireNamespace("gtsummary", quietly = TRUE)) {
    expect_error(gtsummary::tbl_svysummary(design), "nis_design")
  }
  withr::local_options(list(survey.lonely.psu = "remove"))
  expect_error(survey::svymean(~LOS, design), "nis_design")
})

test_that("lazy grouping preserves key types and grouped covariance", {
  withr::local_options(list(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE))
  withr::local_options(list(easyNIS.duckdb_config = list(threads = 2L)))
  query <- suppressWarnings(nis_open(nis_example(2019:2020))) |>
    dplyr::mutate(
      grp = ifelse(AGE > 50, "older", "younger"),
      female_flag = FEMALE == 1L,
      los_days = ifelse(HOSP_NIS == 2L, NA_real_, LOS)
    )
  design <- nis_survey(query, weights = DISCWT / 2)
  reference <- lazy_reference(dplyr::mutate(query, DISCWT = DISCWT / 2))
  for (by in list(~YEAR, ~ factor(YEAR), ~grp, ~female_flag, ~ YEAR + grp)) {
    fit <- survey::svyby(~los_days, by, design, survey::svymean, na.rm = TRUE, covmat = TRUE)
    ref <- survey::svyby(~los_days, by, reference, survey::svymean, na.rm = TRUE, covmat = TRUE)
    expect_lazy_stat(fit, ref)
    expect_equal(as.data.frame(fit), as.data.frame(ref), ignore_attr = TRUE, tolerance = 1e-8)
  }
})

test_that("lazy lonely-PSU options match survey on sampled and domain singletons", {
  withr::local_options(list(easyNIS.duckdb_config = list(threads = 2L)))
  query <- suppressWarnings(nis_open(nis_example(2019:2020))) |>
    dplyr::mutate(NIS_STRATUM = ifelse(HOSP_NIS == 2L, 999L, NIS_STRATUM))
  design <- nis_survey(query)
  reference <- lazy_reference(query)
  withr::local_options(list(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE))
  expect_error(survey::svytotal(~LOS, design), "one PSU")
  withr::local_options(list(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE))
  expect_lazy_stat(survey::svytotal(~LOS, design), survey::svytotal(~LOS, reference))
  expect_lazy_stat(
    suppressWarnings(survey::svytotal(~LOS, subset(design, HOSP_NIS <= 5L))),
    suppressWarnings(survey::svytotal(~LOS, subset(reference, HOSP_NIS <= 5L)))
  )
})
