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
