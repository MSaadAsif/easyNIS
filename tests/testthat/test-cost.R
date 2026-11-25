test_that("nis_cost validates each input boundary", {
  valid <- data.frame(YEAR = 2020, TOTCHG = 1000, CCR_NIS = 0.25)

  expect_error(nis_cost(list(), 2020), "collected data frame")
  expect_error(nis_cost(valid, 2020, charges = character()), "single column name")
  expect_error(nis_cost(valid, 2020, charges = c("TOTCHG", "OTHER")),
    "single column name")
  expect_error(nis_cost(valid, 2020, charges = NA_character_),
    "single column name")
  expect_error(nis_cost(valid, NA_real_), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, 2020.5), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, c(2020, 2021)), "one year from 2012 through 2024")

  valid$YEAR <- "2020"
  expect_error(nis_cost(valid, 2020), "must be numeric")
})

test_that("nis_cost_provenance validates its supported inputs", {
  expect_null(nis_cost_provenance(data.frame()))
  expect_error(nis_cost_provenance(list()), "data frame or survey design")
})

test_that("cost validation identifies the public operation", {
  records <- data.frame(YEAR = 2020L, TOTCHG = 100, CCR_NIS = 0.5)
  condition <- tryCatch(nis_cost(records, 2020.5), error = identity)
  expect_s3_class(condition, "error")
  expect_identical(rlang::call_name(conditionCall(condition)), "nis_cost")
})
