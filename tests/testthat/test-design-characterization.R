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
  expect_equal(coef(survey::svytotal(~AGE, design)), coef(survey::svytotal(~AGE, reference)))
  expect_equal(survey::SE(survey::svytotal(~AGE, design)), survey::SE(survey::svytotal(~AGE, reference)))
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
  expect_identical(as.character(conditionCall(invalid_charges)[[1]]), "nis_design")
  expect_s3_class(invalid_annualize, "rlang_error")
  expect_identical(conditionMessage(invalid_annualize), "`annualize` must be `TRUE` or `FALSE`.")
  expect_identical(as.character(conditionCall(invalid_annualize)[[1]]), "nis_design")
  expect_s3_class(missing_design, "rlang_error")
  expect_match(conditionMessage(missing_design), "`.data` is missing design columns")

  invalid_design <- rlang::catch_cnd(nis_reweight(NULL, 1))
  expect_identical(as.character(conditionCall(invalid_design)[[1]]), "nis_reweight")
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

test_that("sample diagnostics count defects separately from valid quarter coverage", {
  valid <- dplyr::tibble(
    YEAR = rep(2015:2016, each = 8L),
    HOSP_NIS = rep(rep(1:2, each = 4L), 2L),
    NIS_STRATUM = 1L,
    DQTR = c(rep(1:4, 2L), rep(c(1, 3, 7, Inf), 2L)),
    DISCWT = seq(2, 17),
    AGE = seq(41, 56),
    eligible = c(rep(c(FALSE, FALSE, FALSE, TRUE), 2L), rep(TRUE, 8L))
  )
  invalid <- dplyr::tibble(
    YEAR = c(2015L, 2016L, 2016L, NA_integer_),
    HOSP_NIS = c(901L, 902L, -903L, 904L),
    NIS_STRATUM = c(1L, 1L, 1L, -1L),
    DQTR = c(1L, 2L, 4L, 3L),
    DISCWT = c(-1, -1, 0, 3),
    AGE = 90,
    eligible = TRUE
  )
  input <- dplyr::bind_rows(valid, invalid)
  reference <- survey::svydesign(
    ids = ~ interaction(YEAR, HOSP_NIS),
    strata = ~YEAR,
    weights = ~ I(DISCWT / 2),
    nest = TRUE,
    data = valid
  ) |>
    subset(eligible)
  factor_quarters <- dplyr::mutate(input, DQTR = factor(DQTR))
  query <- duckdb_query_fixture(input)
  for (data in list(input, factor_quarters, query)) {
    warnings <- character()
    design <- withCallingHandlers(
      nis_design(data, eligible, keep = AGE, annualize = TRUE),
      warning = function(condition) {
        warnings <<- c(warnings, conditionMessage(condition))
        invokeRestart("muffleWarning")
      }
    )
    expect_length(warnings, 3L)
    expect_match(warnings[[1L]], "Affected valid years: 2015: 1, 2016: 2", fixed = TRUE)
    expect_match(warnings[[2L]], "2016 (Q1, Q3)", fixed = TRUE)
    expect_match(warnings[[3L]], "only ICD-10-coded 2015 discharges", fixed = TRUE)
    excluded <- attr(design, "nis_excluded")
    expect_equal(excluded$total, 4)
    expect_equal(excluded$by_field, c(YEAR = 1, HOSP_NIS = 1, NIS_STRATUM = 1, DISCWT = 3))
    expect_equal(excluded$by_year, dplyr::tibble(YEAR = 2015:2016, n = c(1, 2)))
    expect_equal(coef(survey::svytotal(~AGE, design)), coef(survey::svytotal(~AGE, reference)))
    expect_equal(survey::SE(survey::svytotal(~AGE, design)), survey::SE(survey::svytotal(~AGE, reference)))
  }
})

test_that("a nonannual DuckDB design does not evaluate unselected quarter data", {
  data <- dplyr::tibble(YEAR = 2020L, HOSP_NIS = rep(1:2, each = 4L), NIS_STRATUM = 1L, DISCWT = 1, AGE = 41:48)
  query <- duckdb_query_fixture(data)
  query <- dplyr::mutate(
    query,
    DQTR = dbplyr::sql(
      "CAST(error('unneeded quarter must not be evaluated') AS INTEGER)"
    )
  )
  expect_message(
    design <- nis_design(query, dplyr::if_else(AGE %in% c(43L, 46L), NA, TRUE), keep = AGE),
    "Treated 2 missing cohort values"
  )
  expect_equal(nrow(design$variables), 6L)
})
