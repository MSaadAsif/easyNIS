test_that("nis_open validation errors retain their public call", {
  condition <- tryCatch(nis_open(tempfile(), years = 2018L), error = identity)

  expect_s3_class(condition, "rlang_error")
  expect_identical(as.character(conditionCall(condition)[[1L]]), "nis_open")
})
