convert_binary_fixture <- function(path, ...) {
  data <- data.frame(
    YEAR = c(2020L, 2020L),
    HOSP_NIS = c(2L, 1L),
    I10_DX1 = c("I509", " "),
    I10_PR1 = c(NA_character_, "02703ZZ"),
    NOTE = c("alpha", "byteprobe")
  )
  for (name in names(list(...))) {
    data[[name]] <- list(...)[[name]]
  }
  writer <- switch(
    tools::file_ext(path),
    dta = haven::write_dta,
    sas7bdat = haven::write_sas,
    sav = haven::write_sav
  )
  # haven's deprecated writer still emits the SAS7BDAT format we need here.
  withr::local_options(lifecycle_verbosity = "quiet")
  writer(data, path)
  path
}

convert_patch_bytes <- function(path, old, new) {
  bytes <- readBin(path, "raw", n = file.size(path))
  start <- grepRaw(old, bytes, fixed = TRUE)
  bytes[seq.int(start, length.out = length(new))] <- new
  writeBin(bytes, path)
}

test_that("statistical files produce discoverable zstd Parquet with release checks", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))

  for (ext in c("dta", "sas7bdat", "sav")) {
    source <- convert_binary_fixture(file.path(root, paste0("NIS_2020_mega.", ext)))
    dest <- withr::local_tempdir()
    annual <- nis_convert(source, dest)
    expect_equal(basename(annual), "NIS_2020.parquet")
    expect_true(dir.exists(annual))
    expect_warning(data <- nis_open(dest), class = "easynis_release_mismatch")
    expect_s3_class(data, "tbl_sql")
    records <- dplyr::collect(data)
    expect_equal(records$HOSP_NIS, c(2, 1))
    expect_equal(records$NOTE, c("alpha", "byteprobe"))
    con <- dbplyr::remote_con(data)
    part <- DBI::dbQuoteString(con, list.files(annual, full.names = TRUE))
    metadata <- DBI::dbGetQuery(con, paste("SELECT DISTINCT compression FROM parquet_metadata(", part, ")"))
    expect_identical(metadata$compression, "ZSTD")
  }
})

test_that("legacy Stata strings can be explicitly decoded as Latin-1", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2020.dta")
  haven::write_dta(data.frame(YEAR = 2020L, NOTE = "cafX"), source, version = 12)
  convert_patch_bytes(source, "cafX", as.raw(c(99, 97, 102, 233)))
  nis_convert(source, root, encoding = "latin1")
  data <- nis_open(root, check_release = FALSE)
  expect_identical(dplyr::collect(data)$NOTE, "caf\u00e9")
})

test_that("conversion rejects malformed types, years, codes, and encodings with locations", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2020.dta")
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  check <- function(pattern) {
    expect_error(nis_convert(source, root), pattern)
    expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
  }

  haven::write_dta(data.frame(I10_DX1 = "I509"), source)
  check("YEAR.*row 1")
  convert_binary_fixture(source, YEAR = c("2020", "2020"))
  check("YEAR.*row 1")
  convert_binary_fixture(source, I10_DX1 = c(123, 456))
  check("I10_DX1.*row 1")
  convert_binary_fixture(source, YEAR = c(2020, -17220))
  check("YEAR.*row 2")
  convert_binary_fixture(source, YEAR = c(2019, 2019))
  check("filename year 2020.*YEAR.*row 1")
  convert_binary_fixture(source, I10_DX40 = c("invl ", "incn"))
  expect_true(dir.exists(nis_convert(source, withr::local_tempdir())))
  convert_binary_fixture(source, I10_DX40 = c("", "I5*9"))
  check("I10_DX40.*row 2")
  convert_binary_fixture(source, I10_DX40 = c("", "I509\n"))
  check("I10_DX40.*row 2")
  convert_binary_fixture(source, I10_PR1 = c("", "027O3ZZ"))
  check("I10_PR1.*row 2")
  convert_binary_fixture(source)
  convert_patch_bytes(source, "byteprobe", as.raw(255))
  check("UTF-8.*NOTE.*row 2")
  convert_binary_fixture(source, I10_DX40 = c("", "codeprobe"))
  convert_patch_bytes(source, "codeprobe", as.raw(255))
  check("UTF-8.*I10_DX40.*row 2")

  source <- file.path(withr::local_tempdir(), "NIS_2014.dta")
  haven::write_dta(data.frame(YEAR = 2014L, DX1 = "I509"), source)
  expect_error(nis_convert(source, root), "DX1.*row 1")
})

test_that("conversion preserves an existing annual directory", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- convert_binary_fixture(file.path(root, "NIS_2020.dta"))
  annual <- file.path(root, "NIS_2020.parquet")
  dir.create(annual)
  writeLines("original", file.path(annual, "keep"))
  expect_error(nis_convert(source, root), "already exists")
  expect_identical(readLines(file.path(annual, "keep")), "original")
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 2L)
})

test_that("conversion validates the coding era of populated slots", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  check <- function(year, fields, pattern = NULL) {
    dest <- withr::local_tempdir()
    source <- file.path(root, paste0("NIS_", year, ".dta"))
    haven::write_dta(as.data.frame(c(list(YEAR = year), fields)), source)
    if (is.null(pattern)) {
      expect_true(dir.exists(nis_convert(source, dest)))
    } else {
      expect_error(nis_convert(source, dest), pattern)
    }
  }
  check(2014L, list(DX1 = "V300", ECODE1 = "E916", I10_DX1 = " "))
  check(2014L, list(I10_DX1 = "I509"), "era.*I10_DX1.*row 1")
  check(2014L, list(ECODE1 = "I509"), "ICD.*ECODE1.*row 1")
  check(2020L, list(ECODE1 = "E916"), "era.*ECODE1.*row 1")
  check(2020L, list(I10_ECAUSE1 = "W19XXXA"))
  check(2020L, list(I10_ECAUSE1 = "W19*"), "ICD.*I10_ECAUSE1.*row 1")
  check(2015L, list(DQTR = 1:4, DX1 = c("V300", NA, NA, NA), I10_DX1 = c(NA, NA, NA, "I509")))
  check(2015L, list(DQTR = 2L, I10_ECAUSE1 = "W19XXXA"), "era.*I10_ECAUSE1.*row 1")
  check(2015L, list(DQTR = 4L, DXVER = 9L, DX1 = "V300"), "era.*DX1.*row 1")
  check(2015L, list(DQTR = NA_integer_, DXVER = 9L, PRVER = 10L, DX1 = "V300", I10_PR1 = "02703ZZ"))
  check(2015L, list(DQTR = 4L, PRVER = 9L, I10_PR1 = "02703ZZ"), "era.*I10_PR1.*row 1")
})

test_that("SPSS labels and user-defined missing values preserve stored values", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2020.sav")
  haven::write_sav(
    data.frame(
      YEAR = haven::labelled(rep(2020, 3), c(release = 2020)),
      PAY1 = haven::labelled_spss(c(1, 9, -88), c(first = 1, unknown = 9), na_values = 9),
      I10_DX1 = haven::labelled(c("I509", "J189", "E119"), c(cardio = "I509"))
    ),
    source
  )
  nis_convert(source, root)
  result <- dplyr::collect(nis_open(root, check_release = FALSE))
  expect_identical(result$YEAR, rep(2020L, 3))
  expect_identical(result$PAY1, c(1, 9, -88))
  expect_identical(result$I10_DX1, c("I509", "J189", "E119"))
})

test_that("exact and partial batch boundaries preserve every source record", {
  skip_if_not_installed("haven")
  skip_if_not(tolower(Sys.getenv("EASYNIS_FULL_TESTS")) %in% c("1", "true"))
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  for (n in c(100000L, 100001L)) {
    root <- withr::local_tempdir()
    source <- file.path(root, "NIS_2020.sav")
    haven::write_sav(data.frame(YEAR = rep(2020L, n), KEY_NIS = seq_len(n)), source)
    output <- nis_convert(source, root)
    expect_length(list.files(output), ceiling(n / 100000))
    records <- nis_open(root, check_release = FALSE)
    result <- dplyr::collect(dplyr::arrange(records, KEY_NIS))
    expect_equal(result$KEY_NIS, seq_len(n))
  }
})

test_that("conversion locates text decoding errors raised inside haven", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2020.sav")
  for (row in 1:2) {
    text <- rep("ok", 2L)
    text[[row]] <- "byteprobe"
    convert_binary_fixture(source, ARBITRARY = text, NOTE = c("a", "b"))
    convert_patch_bytes(source, "byteprobe", as.raw(255))
    expect_error(nis_convert(source, root), paste0("encoding.*ARBITRARY.*row ", row))
    expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
  }

  convert_binary_fixture(
    source,
    HOSP_NIS = haven::labelled(c(2, 1), c(second = 2)),
    NOTE = c("wordprobe", "wordprobe"),
    ARBITRARY = c("plain", "byteprobe")
  )
  bytes <- readBin(source, "raw", n = file.size(source))
  header <- writeBin(c(7L, 3L, 4L, 8L), raw(), size = 4L, endian = "little")
  code_page <- grepRaw(header, bytes, fixed = TRUE) + 44L
  bytes[seq.int(code_page, length.out = 4L)] <- writeBin(932L, raw(), size = 4L, endian = "little")
  writeBin(bytes, source)
  convert_patch_bytes(source, "wordprobe", as.raw(c(0x82, 0xa0)))
  convert_patch_bytes(source, "byteprobe", as.raw(c(0x82, 0x20)))
  expect_error(nis_convert(source, root), "encoding in column \`?ARBITRARY\`? at source row 2")
})

test_that("truncated Stata sources cannot publish Parquet", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- convert_binary_fixture(file.path(root, "NIS_2020.dta"))
  bytes <- readBin(source, "raw", n = file.size(source))
  writeBin(bytes[seq_len(grepRaw("byteprobe", bytes, fixed = TRUE) + 2L)], source)
  expect_error(nis_convert(source, root), "read|row", ignore.case = TRUE)
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
})

test_that("conversion refuses to publish a part with missing rows", {
  skip_if_not_installed("haven")
  root <- withr::local_tempdir()
  source <- convert_binary_fixture(file.path(root, "NIS_2020.dta"))
  copy <- nis_convert_copy_batch
  local_mocked_bindings(nis_convert_copy_batch = function(con, data, path) {
    copy(con, data[-1L, ], path)
  })
  expect_error(nis_convert(source, root), "row count mismatch.*2 source rows.*wrote 1")
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
})

test_that("an error after staging an earlier part removes every temporary file", {
  skip_if_not_installed("haven")
  skip_if_not(tolower(Sys.getenv("EASYNIS_FULL_TESTS")) %in% c("1", "true"))
  root <- withr::local_tempdir()
  source <- file.path(root, "NIS_2020.dta")
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L, temp_directory = root))
  n <- 100001L
  haven::write_dta(data.frame(YEAR = c(rep(2020L, n - 1L), 2019L)), source)
  expect_error(nis_convert(source, root), "YEAR.*row 100001")
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), basename(source))
})
