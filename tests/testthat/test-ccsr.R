expect_ccsr_call <- function(expr, name) {
  condition <- tryCatch(eval(substitute(expr), envir = parent.frame()),
    error = identity)
  expect_s3_class(condition, "error")
  expect_identical(rlang::call_name(conditionCall(condition)), name)
  invisible(condition)
}

test_that("nis_ccsr_codes reads the Excel mapping sheet and honours defaults", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)

  expect_equal(nis_ccsr_codes(path, "ZZZ001"), c("X100", "X101"))
  expect_equal(nis_ccsr_codes(path, "zzz002"), c("X101", "X102", "X200"))
  expect_equal(nis_ccsr_codes(path, c("ZZZ001", "ZZZ003")),
    c("X100", "X101", "X200", "Y300", "Y30A"))
  expect_equal(nis_ccsr_codes(path, "ZZZ002", default_only = TRUE),
    c("X101", "X102"))
  expect_equal(nis_ccsr_codes(path, "ZZZ003", default_only = TRUE),
    c("X200", "Y30A"))
})

test_that("nis_ccsr_codes reads the wide comma-separated layout", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_wide_csv(path)

  expect_equal(nis_ccsr_codes(path, "ZZZ001"), c("X100", "X101"))
  expect_equal(nis_ccsr_codes(path, "ZZZ002"), c("X101", "X102", "X200"))
  expect_equal(nis_ccsr_codes(path, "ZZZ002", default_only = TRUE),
    c("X101", "X102"))
  expect_equal(nis_ccsr_codes(path, "ZZZ003", default_only = TRUE), "X200")
})

test_that("nis_ccsr_codes rejects bad input clearly", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)

  expect_error(nis_ccsr_codes(path, "NOPE01"), "NOPE01")
  expect_error(nis_ccsr_codes(path, c("ZZZ001", "NOPE01", "NOPE02")), "NOPE02")
  expect_error(nis_ccsr_codes(path, character()), "categories")
  expect_error(nis_ccsr_codes(path, NA_character_), "categories")
  expect_error(nis_ccsr_codes(path, "ZZZ001", default_only = NA), "default_only")
  expect_error(nis_ccsr_codes(tempfile(fileext = ".xlsx"), "ZZZ001"),
    "existing CCSR")

  other <- tempfile(fileext = ".csv")
  on.exit(unlink(other), add = TRUE)
  writeLines(c("a,b", "1,2"), other)
  expect_error(nis_ccsr_codes(other, "ZZZ001"), "reference file")
})

test_that("CCSR errors retain their public or reader call", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)

  expect_ccsr_call(nis_ccsr_codes(path, character()), "nis_ccsr_codes")
  expect_ccsr_call(nis_ccsr_codes(path, "ZZZ001", default_only = NA),
    "nis_ccsr_codes")
  expect_ccsr_call(nis_ccsr_codes(path, "NOPE01"), "nis_ccsr_codes")
  procedure <- tempfile(fileext = ".csv")
  on.exit(unlink(procedure), add = TRUE)
  writeLines(c("'ICD-10-PCS','PRCCSR'", "'0AB0001','ZZP001'"), procedure)
  expect_ccsr_call(nis_ccsr_codes(procedure, "ZZP001", default_only = TRUE),
    "nis_ccsr_codes")
  expect_ccsr_call(nis_ccsr_codes(tempfile(fileext = ".xlsx"), "ZZZ001"),
    "read_ccsr_map")

  malformed <- tempfile(fileext = ".csv")
  on.exit(unlink(malformed), add = TRUE)
  writeLines(c("a,b", "1,2"), malformed)
  expect_ccsr_call(nis_ccsr_codes(malformed, "ZZZ001"), "read_ccsr_map")

  bad_codes <- tempfile(fileext = ".csv")
  on.exit(unlink(bad_codes), add = TRUE)
  writeLines(c("'ICD-10-CM CODE','CCSR CATEGORY 1'", "'TOOLONG88','ZZZ001'"),
    bad_codes)
  expect_ccsr_call(nis_ccsr_codes(bad_codes, "ZZZ001"), "read_ccsr_map")

  empty <- tempfile(fileext = ".csv")
  on.exit(unlink(empty), add = TRUE)
  writeLines(character(), empty)
  expect_ccsr_call(nis_ccsr_codes(empty, "ZZZ001"), "read_ccsr_source")

  malformed_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(malformed_csv), add = TRUE)
  writeLines(c("'ICD-10-CM CODE','CCSR CATEGORY 1'", "'X100'"),
    malformed_csv)
  expect_ccsr_call(nis_ccsr_codes(malformed_csv, "ZZZ001"), "read_ccsr_source")

  workbook <- tempfile(fileext = ".xlsx")
  on.exit(unlink(workbook), add = TRUE)
  write_ccsr_xlsx(workbook, sheet = "Invented sheet")
  expect_ccsr_call(nis_ccsr_codes(workbook, "ZZZ001"), "read_ccsr_source")
  write_ccsr_xlsx(workbook, header = c("Invented header", "Description",
    "CCSR Category", "CCSR Category Description",
    "Inpatient Default CCSR (Y/N/X)"))
  expect_ccsr_call(nis_ccsr_codes(workbook, "ZZZ001"), "read_ccsr_source")
})

test_that("procedure files have no default category", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c(
    "'ICD-10-PCS','ICD-10-PCS DESCRIPTION','PRCCSR','PRCCSR DESCRIPTION'",
    "'0AB0001','d','ZZP001','c'",
    "'0AB0002','d','ZZP001','c'",
    "'0AC0001','d','ZZP002','c'"
  ), path)

  expect_equal(nis_ccsr_codes(path, "ZZP001"), c("0AB0001", "0AB0002"))
  expect_error(nis_ccsr_codes(path, "ZZP001", default_only = TRUE),
    "no default")
})

test_that("CCSR codes feed nis_flag_dx and nis_flag_pr as prefixes", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_ccsr_xlsx(path)
  codes <- nis_ccsr_codes(path, "ZZZ002", default_only = TRUE)

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
  writeLines(c(
    "'ICD-10-CM CODE','ICD-10-CM CODE DESCRIPTION','Default CCSR CATEGORY IP','Default CCSR CATEGORY DESCRIPTION IP','CCSR CATEGORY 1','CCSR CATEGORY 1 DESCRIPTION'",
    "'X100','Invented disease, type one','ZZZ001','Invented, category','ZZZ001','Invented, category'",
    "'X101','Invented's disease','ZZZ002','Owner's category','ZZZ002','Owner's category'",
    "'X102','Both, and Invented's, here','ZZZ002','c','ZZZ002',''",
    "'X.103','d','ZZZ001','c','ZZZ001','c'"
  ), path)

  expect_equal(nis_ccsr_codes(path, "ZZZ001"), c("X100", "X103"))
  expect_equal(nis_ccsr_codes(path, "ZZZ002"), c("X101", "X102"))
  expect_equal(nis_ccsr_codes(path, "ZZZ002", default_only = TRUE),
    c("X101", "X102"))
})

test_that("malformed CSV rows and non-ICD codes are rejected clearly", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  header <- "'ICD-10-CM CODE','ICD-10-CM CODE DESCRIPTION','CCSR CATEGORY 1'"

  writeLines(c(header, "'X100','d','ZZZ001'", "'X101','d','x','ZZZ001'"), path)
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "Line 3")

  writeLines(c(header, "'X100','d','ZZZ001'", "X101,d,ZZZ001"), path)
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "well-formed")

  writeLines(c(header, "'Invented disease','d','ZZZ001'"), path)
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "not ICD-10 codes")

  writeLines(c(header, "'AB','d','ZZZ001'"), path)
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "not ICD-10 codes")

  writeLines(character(), path)
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "empty")
})

test_that("plain double-quoted CSV files still parse", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c(
    'ICD-10-CM CODE,ICD-10-CM CODE DESCRIPTION,CCSR CATEGORY 1',
    'X100,"Invented, disease",ZZZ001',
    'X101,d,ZZZ002'
  ), path)
  expect_equal(nis_ccsr_codes(path, "ZZZ001"), "X100")
})

test_that("a byte-order mark before the header is tolerated", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(
    "'ICD-10-CM CODE','CCSR CATEGORY 1'\n'X100','ZZZ001'\n"))), path)
  expect_equal(nis_ccsr_codes(path, "ZZZ001"), "X100")
})

test_that("single-quoted CSV headers without rows return an empty mapping", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines("'ICD-10-CM CODE','CCSR CATEGORY 1'", path)

  mapping <- read_ccsr_csv(path)
  expect_equal(dim(mapping), c(0L, 2L))
  expect_equal(names(mapping), c("ICD-10-CM CODE", "CCSR CATEGORY 1"))
})

test_that("CCSR workbooks require one mapping sheet and an ICD-10 header", {
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)

  write_ccsr_xlsx(path, sheet = "Invented sheet")
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "needs one")

  write_ccsr_xlsx(path, header = c("Invented header", "Description",
    "Category", "Category description", "Default"))
  expect_error(nis_ccsr_codes(path, "ZZZ001"), "No header row")
})
