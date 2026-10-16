test_that("nis_label maps common codes, missing sentinels, and preserves labels", {
  data <- dplyr::tibble(
    DIED = c(0, 1, -9),
    FEMALE = c(0, 1, -8),
    RACE = c(1, 2, -9),
    PAY1 = c(1, 2, 3),
    DISPUNIFORM = c(20, 21, 99),
    AGE = c(40, -9, -8),
    LOS = c(2, -6, 5),
    ynel1 = structure(c(0, 1, NA_real_), label = "Existing Elixhauser label")
  )

  labelled <- nis_label(data)
  expect_identical(levels(labelled$DIED), c("No", "Yes"))
  expect_identical(as.character(labelled$DIED), c("No", "Yes", NA_character_))
  expect_identical(levels(labelled$FEMALE), c("Male", "Female"))
  expect_identical(levels(labelled$RACE)[[1L]], "White")
  expect_identical(levels(labelled$PAY1)[[1L]], "Medicare")
  expect_identical(as.character(labelled$DISPUNIFORM), c(
    "Died in hospital", "Discharged to court/law enforcement",
    "Alive, destination unknown"
  ))
  expect_true(is.na(labelled$AGE[[2L]]))
  expect_true(is.na(labelled$AGE[[3L]]))
  expect_true(is.na(labelled$LOS[[2L]]))
  expect_identical(attr(labelled$AGE, "label"), "Age, years")
  expect_identical(attr(labelled$PAY1, "label"), "Primary payer")
  expect_identical(attr(labelled$ynel1, "label"), "Existing Elixhauser label")
  expect_identical(nis_label(labelled), labelled)
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
})
