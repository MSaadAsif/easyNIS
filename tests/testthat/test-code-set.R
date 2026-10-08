test_that("code declarations retain provenance and leading zeros", {
  set <- invented_code_set("0012345", "ICD10PCS")
  expect_identical(set$matching_codes, "0012345")
  expect_identical(set$valid_years, 2017:2022)
  expect_identical(set$review_status, "user_supplied_not_verified")
  expect_identical(set$valid_quarters, 1:4)
  set <- invented_code_set(" a00.1 ", normalize = TRUE)
  expect_identical(set$codes, " a00.1 ")
  expect_identical(set$matching_codes, "A001")
  expect_identical(invented_code_set("A00", match = "prefix")$match, "prefix")
  expect_identical(invented_code_set("0", "ICD10PCS", match = "prefix")$codes, "0")
})

test_that("malformed or ambiguous sets cannot define a cohort", {
  for (codes in list(1, character(), NA_character_, "", "A_01", "A%", "A.*",
                    "A.001", "A00..1", "A00.", "AA0", "100", "A0012345")) {
    expect_error(invented_code_set(codes), "codes|syntax")
  }
  for (codes in c("A.001", "A00..1")) {
    expect_error(invented_code_set(codes, normalize = TRUE), "syntax")
  }
  for (code in c("001234", "00123456", "001I345", "001O345", "001.2345")) {
    expect_error(invented_code_set(code, "ICD10PCS", normalize = TRUE), "syntax")
  }
  expect_error(invented_code_set(c("a00.1", "A001"), normalize = TRUE), "Duplicate")
  expect_error(invented_code_set(c("A001", "A001")), "Duplicate")
  expect_error(invented_code_set(normalize = NA), "TRUE or FALSE")
  expect_error(nis_code_set("A001", "ICD10CM", numeric(), "1", "source", "author"),
               "non-empty")
  expect_error(nis_code_set("A001", "ICD10CM", 2022.5, "1", "source", "author"),
               "whole")
  expect_error(invented_code_set(valid_quarters = c(1, 5)), "quarters")
  expect_error(nis_code_set("A001", "ICD10CM", 2022, "", "source", "author"),
               "version")
  for (field in c("version", "source", "author")) {
    args <- list(codes = "A001", system = "ICD10CM", valid_years = 2022,
                 version = "1", source = "source", author = "author")
    args[[field]] <- " \t\r\n"
    expect_error(do.call(nis_code_set, args), "non-whitespace provenance")
  }
})
