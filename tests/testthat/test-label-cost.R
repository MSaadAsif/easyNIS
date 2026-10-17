test_that("labels require collected data", {
  expect_error(nis_label(list(AGE = 40)), "collected data frame")
})

test_that("cost adjustment validates inputs and preserves missing amounts", {
  data <- data.frame(YEAR = 2020, TOTCHG = c(NA_real_, 1000),
    CCR_NIS = c(0.25, NA_real_))
  adjusted <- nis_cost(data, dollars = 2020)
  expect_true(all(is.na(adjusted$cost_adj)))
  expect_equal(as.numeric(adjusted$charges_adj), c(NA_real_, 1000))
  expect_error(nis_cost(data["YEAR"], 2020), "missing required")
  data$TOTCHG <- as.character(data$TOTCHG)
  expect_error(nis_cost(data, 2020), "must be numeric")
  data$TOTCHG <- c(NA_real_, 1000)
  data$YEAR <- c(NA_real_, 2025)
  expect_error(nis_cost(data, 2020), "without a CPI-U index")
  for (years in list(numeric(), NA_real_, 2011, 2025, 2019.5)) {
    expect_error(nis_example(years), "whole years")
  }
})

test_that("nis_label maps common codes and preserves existing labels", {
  data <- dplyr::tibble(
    DIED = c(0, 1, 0),
    FEMALE = c(0, 1, 0),
    RACE = c(1, 2, 3),
    PAY1 = c(1, 2, 3),
    DISPUNIFORM = c(20, 21, 99),
    PL_NCHS2 = c(21, 22, 21),
    TOTCHG_2023 = c(1000, 2000, 3000),
    AGE = c(40, -9, -8),
    LOS = c(2, -6, 5),
    ynel1 = structure(c(0, 1, NA_real_), label = "Existing Elixhauser label")
  )

  expect_warning(labelled <- nis_label(data), "Unknown code.*DISPUNIFORM")
  expect_identical(levels(labelled$DIED), c("No", "Yes"))
  expect_identical(as.character(labelled$DIED), c("No", "Yes", "No"))
  expect_identical(levels(labelled$FEMALE), c("Male", "Female"))
  expect_identical(levels(labelled$RACE)[[1L]], "White")
  expect_identical(levels(labelled$PAY1)[[1L]], "Medicare")
  expect_identical(as.character(labelled$DISPUNIFORM), c(
    "Died in hospital", "Code 21",
    "Alive, destination unknown"
  ))
  # 2023-only fields have no audited labels, so they pass through untouched.
  expect_identical(labelled$PL_NCHS2, data$PL_NCHS2)
  expect_identical(labelled$TOTCHG_2023, data$TOTCHG_2023)
  expect_equal(as.numeric(labelled$AGE), c(40, -9, -8))
  expect_equal(as.numeric(labelled$LOS), c(2, -6, 5))
  expect_identical(attr(labelled$AGE, "label"), "Age, years")
  expect_identical(attr(labelled$PAY1, "label"), "Expected primary payer")
  expect_identical(attr(labelled$ynel1, "label"), "Existing Elixhauser label")
  expect_identical(nis_label(labelled), labelled)
})

test_that("nis_label retains unknown codes and warns once per variable", {
  data <- dplyr::tibble(
    PAY1 = c(1, 7, 8),
    H_CONTRL = c(1, 4, 5)
  )
  warnings <- character()
  labelled <- withCallingHandlers(
    nis_label(data),
    warning = function(warning) {
      warnings <<- c(warnings, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )

  expect_length(warnings, 2L)
  expect_match(warnings[[1L]], "PAY1")
  expect_match(warnings[[2L]], "H_CONTRL")
  expect_identical(as.character(labelled$PAY1), c(
    "Medicare", "Code 7", "Code 8"
  ))
  expect_identical(as.character(labelled$H_CONTRL), c(
    "Government, non-federal", "Code 4", "Code 5"
  ))
  expect_identical(nis_label(labelled), labelled)
})

test_that("nis_label applies audited labels without guessing unsupported codes", {
  data <- dplyr::tibble(
    I10_INJURY = c(0, 1, 2, 0, 1),
    I10_BIRTH = c(0:3, 0),
    I10_SERVICELINE = 1:5,
    APRDRG_RISK_MORTALITY = 0:4,
    APRDRG_SEVERITY = 0:4,
    GRPCI = c(0:2, 0, 1),
    PAY1 = 1L,
    ZIPINC_QRTL = 1L,
    H_CONTRL = 1L,
    ynel3 = structure(c(0, 1, 0, 1, 0), label = "Existing Elixhauser label"),
    ynch2 = structure(c(1, 0, 1, 0, 1), label = "Existing Charlson label")
  )

  labelled <- nis_label(data)
  expect_identical(as.character(labelled$I10_INJURY)[1:3], c(
    "No injury", "Injury, first-listed", "Injury, other than first-listed"
  ))
  expect_equal(as.numeric(labelled$I10_BIRTH), c(0:3, 0))
  expect_identical(attr(labelled$I10_BIRTH, "label"), "ICD-10-CM birth indicator")
  expect_type(labelled$I10_SERVICELINE, "integer")
  expect_equal(as.numeric(labelled$I10_SERVICELINE), 1:5)
  expect_identical(attr(labelled$I10_SERVICELINE, "label"),
    "ICD-10-CM/PCS service line indicator")
  expect_identical(levels(labelled$APRDRG_RISK_MORTALITY)[[1L]],
    "No class specified")
  expect_identical(levels(labelled$APRDRG_SEVERITY)[[1L]],
    "No class specified")
  expect_identical(as.character(labelled$GRPCI), c(
    "No comorbidities", "One comorbidity", "Two or more comorbidities",
    "No comorbidities", "One comorbidity"
  ))
  expect_identical(as.character(labelled$ynel3), c("No", "Yes", "No", "Yes", "No"))
  expect_identical(as.character(labelled$ynch2), c("Yes", "No", "Yes", "No", "Yes"))
  expect_identical(attr(labelled$ynel3, "label"), "Existing Elixhauser label")
  expect_identical(attr(labelled$ynch2, "label"), "Existing Charlson label")
  expect_identical(attr(labelled$PAY1, "label"), "Expected primary payer")
  expect_identical(attr(labelled$ZIPINC_QRTL, "label"),
    "Median household income national quartile (patient ZIP)")
  expect_identical(attr(labelled$H_CONTRL, "label"), "Hospital control/ownership")
})

test_that("nis_cost applies CPI-U adjustments and labels the results", {
  data <- dplyr::tibble(
    YEAR = c(2018, 2020),
    TOTCHG = c(1000, 2000),
    CCR_NIS = c(0.25, 0.30)
  )
  adjusted <- nis_cost(data, dollars = 2022)
  expect_equal(as.numeric(adjusted$charges_adj), c(
    1000 * 292.655 / 251.107,
    2000 * 292.655 / 258.811
  ))
  expect_equal(as.numeric(adjusted$cost_adj),
    as.numeric(adjusted$charges_adj) * data$CCR_NIS)
  expect_identical(attr(adjusted$cost_adj, "label"), "Hospital cost (2022 USD)")
  expect_identical(attr(adjusted$charges_adj, "label"), "Total charges (2022 USD)")
  expect_error(nis_cost(data, dollars = 2025), "2012 through 2024")

  other <- dplyr::tibble(YEAR = 2023, TOTCHG = 1, TOTCHG_2023 = 4000, CCR_NIS = 0.5)
  explicit <- nis_cost(other, dollars = 2023, charges = "TOTCHG_2023")
  expect_equal(as.numeric(explicit$charges_adj), 4000)
  expect_equal(as.numeric(explicit$cost_adj), 2000)
  expect_equal(as.numeric(nis_cost(other, dollars = 2023)$charges_adj), 1)
  expect_error(nis_cost(other, dollars = 2023, charges = "MISSING"), "MISSING")
})

test_that("common labels and cost adjustment work in experimental ICD-9 years", {
  data <- dplyr::tibble(
    YEAR = 2012:2015, PAY1 = rep(1L, 4L), DIED = c(0L, 1L, 0L, 1L),
    DX1 = rep("12345", 4L), TOTCHG = rep(1000, 4L), CCR_NIS = rep(0.25, 4L)
  )
  labelled <- nis_label(data)
  expect_identical(as.character(labelled$PAY1), rep("Medicare", 4L))
  expect_identical(as.character(labelled$DIED), c("No", "Yes", "No", "Yes"))
  expect_identical(labelled$DX1, data$DX1)
  adjusted <- nis_cost(data, dollars = 2024)
  expect_equal(as.numeric(adjusted$cost_adj),
    250 * 313.689 / c(229.594, 232.957, 236.736, 237.017))
})
