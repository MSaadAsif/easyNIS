expect_ccsr_call <- function(expr, message) {
  condition <- tryCatch(eval(substitute(expr), envir = parent.frame()), error = identity)
  testthat::expect_s3_class(condition, "error")
  testthat::expect_match(conditionMessage(condition), message)
  testthat::expect_identical(rlang::call_name(conditionCall(condition)), "nis_ccsr_codes")
  invisible(condition)
}

test_that("nis_ccsr_codes reads the Excel mapping sheet and honours defaults", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)

  expect_equal(nis_ccsr_codes("ZZZ001", file = path), c("X100", "X101"))
  expect_equal(nis_ccsr_codes("zzz002", file = path), c("X101", "X102", "X200"))
  expect_equal(nis_ccsr_codes(c("ZZZ001", "ZZZ003"), file = path), c("X100", "X101", "X200", "Y300", "Y30A"))
  expect_equal(nis_ccsr_codes("ZZZ002", file = path, default_only = TRUE), c("X101", "X102"))
  expect_equal(nis_ccsr_codes("ZZZ003", file = path, default_only = TRUE), c("X200", "Y30A"))
})

test_that("nis_ccsr_codes reads the wide comma-separated layout", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_wide_csv(path)

  expect_equal(nis_ccsr_codes("ZZZ001", file = path), c("X100", "X101"))
  expect_equal(nis_ccsr_codes("ZZZ002", file = path), c("X101", "X102", "X200"))
  expect_equal(nis_ccsr_codes("ZZZ002", file = path, default_only = TRUE), c("X101", "X102"))
  expect_equal(nis_ccsr_codes("ZZZ003", file = path, default_only = TRUE), "X200")
})

test_that("nis_ccsr_codes rejects bad input clearly", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_wide_csv(path)

  expect_error(nis_ccsr_codes("NOPE01", file = path), "NOPE01")
  expect_error(nis_ccsr_codes(c("ZZZ001", "NOPE01", "NOPE02"), file = path), "NOPE02")
  expect_error(nis_ccsr_codes(character(), file = path), "categories")
  expect_error(nis_ccsr_codes(NA_character_, file = path), "categories")
  expect_error(nis_ccsr_codes("ZZZ001", file = path, default_only = NA), "default_only")
  expect_error(nis_ccsr_codes("ZZZ001", file = tempfile(fileext = ".xlsx")), "existing CCSR")

  other <- tempfile(fileext = ".csv")
  on.exit(unlink(other), add = TRUE)
  writeLines(c("a,b", "1,2"), other)
  expect_error(nis_ccsr_codes("ZZZ001", file = other), "reference file")
})

test_that("malformed CCSR inputs identify the public lookup call", {
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))

  writeLines(c("a,b", "1,2"), path)
  expect_ccsr_call(nis_ccsr_codes("ZZZ001", file = path), "reference file")

  writeLines(c("'ICD-10-CM CODE','CCSR CATEGORY 1'", "'TOOLONG88','ZZZ001'"), path)
  expect_ccsr_call(nis_ccsr_codes("ZZZ001", file = path), "not ICD-10 codes")

  writeLines(character(), path)
  expect_ccsr_call(nis_ccsr_codes("ZZZ001", file = path), "empty")

  writeLines(c("'ICD-10-CM CODE','CCSR CATEGORY 1'", "'X100'"), path)
  expect_ccsr_call(nis_ccsr_codes("ZZZ001", file = path), "well-formed single-quoted CSV")
})

test_that("procedure files have no default category", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      "'ICD-10-PCS','ICD-10-PCS DESCRIPTION','PRCCSR','PRCCSR DESCRIPTION'",
      "'0AB0001','d','ZZP001','c'",
      "'0AB0002','d','ZZP001','c'",
      "'0AC0001','d','ZZP002','c'"
    ),
    path
  )

  expect_equal(nis_ccsr_codes("ZZP001", file = path), c("0AB0001", "0AB0002"))
  expect_error(nis_ccsr_codes("ZZP001", file = path, default_only = TRUE), "no default")
})

test_that("CCSR codes feed nis_flag_dx and nis_flag_pr as prefixes", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)
  codes <- nis_ccsr_codes("ZZZ002", file = path, default_only = TRUE)

  data <- dplyr::tibble(
    I10_DX1 = c("X101", "X102", "X200", "Q1"),
    I10_DX2 = c("Q1", "Q1", "X101", NA_character_)
  )
  flagged <- nis_flag_dx(data, grp = codes, position = "principal")
  expect_equal(flagged$grp, c(TRUE, TRUE, FALSE, FALSE))
  flagged <- nis_flag_dx(data, grp = codes)
  expect_equal(flagged$grp, c(TRUE, TRUE, TRUE, FALSE))
})

test_that("quoted descriptions with commas and apostrophes do not shift fields", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      paste0(
        "'ICD-10-CM CODE','ICD-10-CM CODE DESCRIPTION','",
        "Default CCSR CATEGORY IP','Default CCSR CATEGORY DESCRIPTION IP',",
        "'CCSR CATEGORY 1','CCSR CATEGORY 1 DESCRIPTION'"
      ),
      "'X100','Invented disease, type one','ZZZ001','Invented, category','ZZZ001','Invented, category'",
      "'X101','Invented's disease','ZZZ002','Owner's category','ZZZ002','Owner's category'",
      "'X102','Both, and Invented's, here','ZZZ002','c','ZZZ002',''",
      "'X.103','d','ZZZ001','c','ZZZ001','c'"
    ),
    path
  )

  expect_equal(nis_ccsr_codes("ZZZ001", file = path), c("X100", "X103"))
  expect_equal(nis_ccsr_codes("ZZZ002", file = path), c("X101", "X102"))
  expect_equal(nis_ccsr_codes("ZZZ002", file = path, default_only = TRUE), c("X101", "X102"))
})

test_that("malformed CSV rows and non-ICD codes are rejected clearly", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  header <- "'ICD-10-CM CODE','ICD-10-CM CODE DESCRIPTION','CCSR CATEGORY 1'"

  writeLines(c(header, "'X100','d','ZZZ001'", "'X101','d','x','ZZZ001'"), path)
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "Line 3")

  writeLines(c(header, "'X100','d','ZZZ001'", "X101,d,ZZZ001"), path)
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "well-formed")

  writeLines(c(header, "'Invented disease','d','ZZZ001'"), path)
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "not ICD-10 codes")

  writeLines(c(header, "'AB','d','ZZZ001'"), path)
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "not ICD-10 codes")

  writeLines(character(), path)
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "empty")
})

test_that("plain double-quoted CSV files still parse", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      "ICD-10-CM CODE,ICD-10-CM CODE DESCRIPTION,CCSR CATEGORY 1",
      "X100,\"Invented, disease\",ZZZ001",
      "X101,d,ZZZ002"
    ),
    path
  )
  expect_equal(nis_ccsr_codes("ZZZ001", file = path), "X100")
})

test_that("standard CSV mappings reject extra and missing record fields", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  header <- "ICD-10-CM CODE,CCSR CATEGORY 1"

  for (row in c("X100,X101,ZZZ001", "X100")) {
    writeLines(c(header, row), path)
    expect_error(nis_ccsr_codes("ZZZ001", file = path), "record field counts")
    writeLines(c(header, "X102,ZZZ001", row), path)
    expect_error(nis_ccsr_codes("ZZZ001", file = path), "record field counts")
  }
})

test_that("standard CSV validation respects quoted commas and multiline records", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      '"ICD-10-CM CODE","Description","CCSR CATEGORY 1"',
      '"X100","Invented, description","ZZZ001"',
      '"X101","Invented ""quoted""',
      'description, continued","ZZZ001"'
    ),
    path
  )
  expect_identical(nis_ccsr_codes("ZZZ001", file = path), c("X100", "X101"))
})

test_that("standard CSV validation accepts multiline headers and checks later records", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  header <- c('"ICD-10-CM', 'CODE","Description","CCSR CATEGORY 1"')
  writeLines(c(header, '"X100","Invented","ZZZ001"'), path)
  expect_identical(nis_ccsr_codes("ZZZ001", file = path), "X100")
  for (row in c('"X100","ZZZ001"', '"X100","Invented","ZZZ001","Extra"')) {
    writeLines(c(header, row), path)
    expect_error(nis_ccsr_codes("ZZZ001", file = path), "record field counts")
  }
})

test_that("a byte-order mark before the header is tolerated", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeBin(
    c(
      as.raw(c(0xef, 0xbb, 0xbf)),
      charToRaw(paste0(
        "'ICD-10-CM CODE','CCSR CATEGORY 1'\n'X100','ZZZ001'\n"
      ))
    ),
    path
  )
  expect_equal(nis_ccsr_codes("ZZZ001", file = path), "X100")
})

test_that("single-quoted CSV headers without rows have no matching categories", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines("'ICD-10-CM CODE','CCSR CATEGORY 1'", path)

  expect_error(nis_ccsr_codes("ZZZ001", file = path), "ZZZ001.*not found")
})

test_that("CCSR workbooks require one mapping sheet and an ICD-10 header", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)

  write_ccsr_xlsx(path, sheet = "Invented sheet")
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "needs one")

  write_ccsr_xlsx(path, header = c("Invented header", "Description", "Category", "Category description", "Default"))
  expect_error(nis_ccsr_codes("ZZZ001", file = path), "No header row")
})
