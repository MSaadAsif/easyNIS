test_that("nis_design preserves year-scoped domain estimates", {
  data <- dplyr::tibble(
    YEAR = rep(2020:2021, each = 4),
    HOSP_NIS = rep(rep(1:2, each = 2), 2),
    NIS_STRATUM = 1,
    DISCWT = c(2, 3, 4, 5, 6, 7, 8, 9),
    include = c(TRUE, NA, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
    AGE = c(40, 50, 60, 70, 42, 52, 62, 72)
  )

  informs <- character()
  design <- withCallingHandlers(
    nis_design(data, include, keep = AGE, annualize = TRUE),
    rlang_message = function(condition) {
      informs <<- c(informs, conditionMessage(condition))
      invokeRestart("muffleMessage")
    }
  )
  reference <- srvyr::as_survey_design(
    dplyr::mutate(
      data,
      .nis_psu = paste(YEAR, HOSP_NIS, sep = "::"),
      .nis_stratum = paste(YEAR, NIS_STRATUM, sep = "::"),
      .nis_weight = DISCWT / 2
    ),
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(include)

  expect_equal(as.integer(design$variables$YEAR), 2020:2021)
  expect_identical(design$variables$.nis_psu, c("2020::1", "2021::1"))
  expect_identical(design$variables$.nis_stratum, c("2020::1", "2021::1"))
  expect_equal(as.numeric(stats::weights(design)), c(1, 3.5))
  expect_equal(coef(survey::svytotal(~AGE, design)),
    coef(survey::svytotal(~AGE, reference)))
  expect_equal(survey::SE(survey::svytotal(~AGE, design)),
    survey::SE(survey::svytotal(~AGE, reference)))
  expect_true(any(grepl("missing cohort value", informs, fixed = TRUE)))
  expect_true(any(grepl("Cohort: 2 discharges", informs, fixed = TRUE)))
})

test_that("nis_design validation conditions retain their classes and text", {
  data <- dplyr::tibble(
    YEAR = 2020,
    HOSP_NIS = 1,
    NIS_STRATUM = 1,
    DISCWT = 1,
    AGE = 40
  )

  invalid_charges <- rlang::catch_cnd(nis_design(data, TRUE, AGE, charges = c("TOTCHG", "TOTCHG_2023")))
  invalid_annualize <- rlang::catch_cnd(nis_design(data, TRUE, AGE, annualize = NA))
  missing_design <- rlang::catch_cnd(nis_design(data["AGE"], TRUE, AGE))

  expect_s3_class(invalid_charges, "rlang_error")
  expect_identical(conditionMessage(invalid_charges), "`charges` must be a single column name.")
  expect_s3_class(invalid_annualize, "rlang_error")
  expect_identical(conditionMessage(invalid_annualize), "`annualize` must be `TRUE` or `FALSE`.")
  expect_s3_class(missing_design, "rlang_error")
  expect_match(conditionMessage(missing_design), "`.data` is missing design columns")
})

test_that("nis_design reports invalid design years and defaults cost dollars", {
  invalid <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L),
    HOSP_NIS = c(1L, 2L, 1L, NA_integer_),
    NIS_STRATUM = 1L,
    DISCWT = c(1, -1, 1, 1),
    include = TRUE,
    AGE = 40
  )

  expect_warning(
    nis_design(invalid, include, keep = AGE),
    "Affected valid years: 2020: 1, 2021: 1."
  )

  costs <- dplyr::tibble(
    YEAR = rep(2020L, 4),
    HOSP_NIS = rep(1:2, each = 2),
    NIS_STRATUM = 1L,
    DISCWT = 1,
    include = c(TRUE, FALSE, TRUE, FALSE),
    AGE = 40,
    TOTCHG = 100,
    CCR_NIS = 0.25
  )
  design <- nis_design(costs, include, keep = c(AGE, TOTCHG, CCR_NIS))

  expect_identical(nis_cost_provenance(design)$base_year, 2020L)
})
