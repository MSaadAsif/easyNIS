test_that("malformed slots do not turn missing canonical diagnoses into zeros", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  control <- data.frame(
    I10_DX1 = c(NA_character_, "", "ZZZ99"),
    DXPOA1 = "Y"
  )
  expect_warning(expected <- nis_comorbidity(control), "2 rows")
  expect_identical(expected$cmrb_n, c(NA_integer_, NA_integer_, 0L))

  for (slot in c("I10_DX0", "I10_DX00", "I10_DX01", "I10_DX02")) {
    data <- control
    data[[slot]] <- "ZZZ99"
    expect_warning(out <- nis_comorbidity(data), "2 rows")
    expect_identical(out[names(expected)], expected)
    expect_identical(out[names(data)], data)
  }
})

test_that("malformed slots cannot supply the required principal column", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  malformed <- data.frame(
    I10_DX0 = "ZZZ99", I10_DX00 = "ZZZ99",
    I10_DX01 = "ZZZ99", I10_DX02 = "ZZZ99"
  )
  for (slot in names(malformed)) {
    expect_error(nis_comorbidity(malformed[slot]), "no ICD-10 diagnosis columns")
  }
  expect_error(nis_comorbidity(malformed), "no ICD-10 diagnosis columns")
  malformed$I10_DX2 <- "ZZZ99"
  expect_error(nis_comorbidity(malformed), "I10_DX1.*required")
})

test_that("sparse reordered canonical slots retain scoring and input columns", {
  skip_if_not_installed("medicalcoder", minimum_version = "0.10.0")
  data <- data.frame(
    KEY = c(3L, 1L, 2L),
    I10_DX10 = c("ZZZ99", NA, NA), DXPOA10 = "N",
    I10_DX1 = c(NA, "ZZZ99", NA), DXPOA1 = "Y",
    I10_DX3 = c(NA, NA, "ZZZ99"), DXPOA3 = "W",
    I10_DX01 = "ZZZ99", DXPOA01 = "N"
  )
  expect_no_warning(out <- nis_comorbidity(data))
  expect_identical(out$cmrb_n, rep(0L, 3L))
  expect_identical(out[names(data)], data)
  canonical <- data[c("I10_DX1", "DXPOA1", "I10_DX3", "DXPOA3",
    "I10_DX10", "DXPOA10")]
  expected <- nis_comorbidity(canonical)
  added <- setdiff(names(out), names(data))
  expect_identical(out[added], expected[added])
})

test_that("canonical suffixes keep principal and secondary POA pairing", {
  data <- data.frame(
    I10_DX10 = "ZZZ99", DXPOA10 = "N",
    I10_DX01 = "ZZZ99", DXPOA01 = "N",
    I10_DX1 = "ZZZ99", DXPOA1 = "Y",
    I10_DX3 = "ZZZ99", DXPOA3 = "W",
    I10_DX0 = "ZZZ99", DXPOA0 = "N"
  )
  columns <- nis_comorbidity_validate_data(data)
  long <- nis_comorbidity_long(data, columns$slots, columns$slot_number, nrow(data))
  expect_identical(long, data.frame(
    .row = c(1L, 1L, 1L), code = rep("ZZZ99", 3L),
    primary = c(0L, 1L, 0L), poa = c(0L, 1L, 1L)
  ))
})
