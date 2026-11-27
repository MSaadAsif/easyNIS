convert_ascii_record <- function(width, starts, values) {
  line <- strrep(" ", width)
  for (i in seq_along(starts)) {
    start <- starts[[i]]
    substr(line, start, start + nchar(values[[i]]) - 1L) <- values[[i]]
  }
  line
}

convert_ascii_2024 <- function() {
  # Positions from SASLoad_NIS_2024_Core.SAS, independent of the package layout.
  convert_ascii_record(
    643L,
    c(1L, 6L, 16L, 27L, 63L, 351L, 538L, 625L),
    c("00002", "9876543210", "-99", "  5.1234567", "I509", "02703ZZ", "0010", "2024")
  )
}

test_that("published ASCII Core layouts convert both ICD eras and 2015 Core", {
  root <- withr::local_tempdir()
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  folder <- file.path(root, "NIS_2024_Core.ASC")
  line <- convert_ascii_2024()
  writeBin(charToRaw(paste0(line, "\r\n", line)), folder)
  nis_convert(folder, root)

  source12 <- file.path(root, "NIS_2012_Core.ASC")
  line12 <- convert_ascii_record(
    504L,
    c(12L, 38L, 285L, 320L, 333L, 499L),
    c("00051234567", "V300", "00001", "0001", "0123", "2012")
  )
  writeBin(charToRaw(paste0(line12, "\n")), source12)
  nis_convert(source12, root)

  source15 <- file.path(root, "NIS_2015_Core.ASC")
  line15 <- convert_ascii_record(86L, c(36L, 56L, 81L), c("00003", "0001", "2015"))
  writeBin(charToRaw(paste0(line15, "\n")), source15)
  nis_convert(source15, root)

  expect_warning(data <- nis_open(root), class = "easynis_release_mismatch")
  expect_s3_class(data, "tbl_sql")
  records <- dplyr::collect(dplyr::arrange(data, YEAR))
  expect_identical(records$YEAR, c(2012L, 2015L, 2024L, 2024L))
  expect_equal(records$DISCWT, c(5.1234567, NA_real_, 5.1234567, 5.1234567))
  expect_equal(records$AGE, rep(NA_integer_, 4L))
  expect_equal(records$KEY_NIS[3:4], rep(9876543210, 2L))
  expect_identical(records$DX1, c("V300", NA, NA, NA))
  expect_identical(records$PR1, c("0123", NA, NA, NA))
  expect_identical(records$I10_DX1, c(NA, NA, "I509", "I509"))
  expect_identical(records$I10_PR1, c(NA, NA, "02703ZZ", "02703ZZ"))
})

test_that("converted ASCII codes support exact regex and exclusion", {
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2024_Core.ASC")
  lines <- rep(convert_ascii_2024(), 3L)
  substr(lines, 6L, 15L) <- sprintf("%010d", 1:3)
  substr(lines[2L], 63L, 69L) <- "I508   "
  substr(lines[3L], 63L, 69L) <- "       "
  writeLines(lines, source)
  nis_convert(source, root)
  data <- nis_open(root, check_release = FALSE)
  flags <- nis_flag_dx(data, case = list(regex = "I50[89]", exclude = "I508"))
  records <- dplyr::collect(dplyr::arrange(flags, KEY_NIS))
  expect_identical(records$I10_DX1, c("I509", "I508", NA))
  expect_identical(records$case, c(TRUE, FALSE, FALSE))
})

test_that("ASCII conversion checks line endings across the read buffer", {
  skip_if_not(tolower(Sys.getenv("EASYNIS_FULL_TESTS")) %in% c("1", "true"))
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2024_Core.ASC")
  line <- convert_ascii_2024()
  n <- (8L * 1024L * 1024L) %/% 645L + 1L
  writeBin(charToRaw(paste0(strrep(paste0(line, "\r\n"), n), line, "\n")), source)
  expect_error(nis_convert(source, root), paste("line ending.*row", n + 1L))
  writeBin(charToRaw(strrep(paste0(line, "\r\n"), n)), source)
  nis_convert(source, root)
  records <- nis_open(root, check_release = FALSE)
  expect_equal(dplyr::collect(dplyr::summarise(records, n = dplyr::n()))$n, n)
})

test_that("ASCII conversion accepts decimal point at either end", {
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2024_Core.ASC")
  lines <- rep(convert_ascii_2024(), 2L)
  substr(lines, 27L, 37L) <- c("   .5000000", "         5.")
  writeLines(lines, source)
  nis_convert(source, root)
  expect_equal(dplyr::collect(nis_open(root, check_release = FALSE))$DISCWT, c(0.5, 5))
  expect_error(nis_convert(source, root), "already exists")
  expect_error(nis_convert(source, root, encoding = "UTF-8"), "encoding.*unset")
})

test_that("ASCII conversion rejects malformed records and cleans staging and spill paths", {
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2024_Core.asc")
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L, temp_directory = root))
  good <- convert_ascii_2024()
  check <- function(bad, pattern) {
    writeBin(c(charToRaw(paste0(good, "\n")), bad, as.raw(10L)), source)
    expect_error(nis_convert(source, root), pattern)
    expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
  }

  check(charToRaw(substr(good, 1L, 642L)), "width.*row 2")
  check(charToRaw(paste0(good, "\r")), "line ending.*row 2")
  writeBin(charToRaw(paste0(good, "\r")), source)
  expect_error(nis_convert(source, root), "line ending.*row 1")
  bad <- charToRaw(good)
  bad[[63L]] <- as.raw(255)
  check(bad, "UTF-8.*I10_DX1.*row 2")
  bad <- good
  substr(bad, 1L, 5L) <- "2.3  "
  check(charToRaw(bad), "HOSP_NIS.*row 2")
  bad <- good
  substr(bad, 625L, 628L) <- "2023"
  check(charToRaw(bad), "YEAR.*row 2")
  bad <- good
  substr(bad, 65L, 65L) <- "*"
  check(charToRaw(bad), "I10_DX1.*row 2")
})
