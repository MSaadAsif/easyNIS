test_that("nis_open stays lazy and unifies the 2022 APR-DRG case drift", {
  path <- nis_example(2017:2022)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  query <- nis_open(path)
  expect_true(inherits(query, "arrow_dplyr_query"))
  expect_true("APRDRG_RISK_MORTALITY" %in% names(query))
  expect_false(any(grepl("^APRDRG_Risk_Mortality$", names(query))))

  aprdrg <- query |>
    dplyr::select(YEAR, APRDRG_RISK_MORTALITY) |>
    dplyr::collect()
  expect_equal(nrow(aprdrg), 576L)
  expect_true(all(aprdrg$APRDRG_RISK_MORTALITY[aprdrg$YEAR == 2022] %in% 0:4))
  expect_true(all(aprdrg$APRDRG_RISK_MORTALITY[aprdrg$YEAR < 2022] %in% 0:4))
  expect_error(nis_open(path, years = 2015), "No NIS Parquet entry")
  expect_error(nis_open(path, years = 2011), "before 2012")
})

test_that("ICD flags match prefixes by slot and behave the same on Arrow", {
  data <- dplyr::tibble(
    I10_DX1 = c("I5090", "J189", "I5", NA_character_, "E119"),
    I10_DX2 = c("J189", "I5022", "0", "I501", "I509"),
    I10_DX3 = c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
    I10_PR1 = c("02L73DK", "0JH60DZ", NA_character_, "02703ZZ", "02L73DK"),
    I10_PR2 = c(NA_character_, "02L73DX", NA_character_, NA_character_, NA_character_)
  )
  data_path <- tempfile("nis-flag-")
  dir.create(data_path)
  on.exit(unlink(data_path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(data_path, "part-0.parquet"))
  query <- arrow::open_dataset(data_path)

  add_flags <- function(.data) {
    .data |>
      nis_flag_dx(any_hf = "i5 0", position = "any") |>
      nis_flag_dx(principal_hf = "I50", position = "principal") |>
      nis_flag_dx(secondary_hf = "I50", position = "secondary") |>
      nis_flag_dx(mixed = c("I1 1.0", "I50", "E1", "J189", "J189"), position = "any") |>
      nis_flag_pr(any_proc = "02L", position = "any") |>
      nis_flag_pr(principal_proc = "02.L", position = "principal")
  }
  expected <- add_flags(data)
  actual <- add_flags(query) |> dplyr::collect()

  expect_identical(actual, expected)
  expect_identical(actual$any_hf, c(TRUE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(actual$principal_hf, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(actual$secondary_hf, c(FALSE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(actual$mixed, c(TRUE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(actual$any_proc, c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$principal_proc, c(TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_error(nis_flag_dx(data, invalid = "I50-"), "letters and numbers")
  expect_error(nis_flag_dx(data, invalid = "I50", invalid = "I51"), "unique")
})

test_that("ICD flags compare stored codes byte for byte and never fail on malformed text", {
  malformed <- rawToChar(as.raw(c(0x49, 0x35, 0x30, 0xff, 0xfe)))
  data <- dplyr::tibble(
    I10_DX1 = c("I509", malformed, NA_character_, "Z515", "i50", "I50é", "E11"),
    I10_DX2 = c(NA_character_, "J18", "Z515", malformed, NA_character_, "I51", "I5")
  )
  data_path <- tempfile("nis-utf8-")
  dir.create(data_path)
  on.exit(unlink(data_path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(data_path, "part-0.parquet"))
  query <- arrow::open_dataset(data_path)

  add_flags <- function(.data) {
    .data |>
      nis_flag_dx(any_hf = c("I50", "I51"), palliative = "Z515", position = "any") |>
      nis_flag_dx(principal_hf = "I50", position = "principal")
  }
  lazy <- add_flags(query)
  expect_true(inherits(lazy, "arrow_dplyr_query"))
  actual <- dplyr::collect(lazy)

  expect_identical(actual$any_hf, c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(actual$palliative, c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(actual$principal_hf, c(TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(add_flags(data), actual)
})

test_that("ICD flags read the current lazy projection, not the stored columns", {
  data <- dplyr::tibble(
    pick = c(1L, 2L, 1L, 2L, 1L),
    I10_DX1 = c("Z0000", "Z0000", "C004", "A1299", NA_character_),
    I10_DX2 = c("C004", "A1299", "Z0000", "Z0000", "Z0000"),
    I10_PR1 = c("0AAAAAA", "0BBBBBB", "0AAAAAA", "0BBBBBB", NA_character_)
  )
  data_path <- tempfile("nis-lazy-")
  dir.create(data_path)
  on.exit(unlink(data_path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(data_path, "part-0.parquet"))
  query <- arrow::open_dataset(data_path)

  prepare_and_flag <- function(.data) {
    .data |>
      dplyr::mutate(
        I10_DX1 = dplyr::if_else(pick == 1L, "A1234", "C004"),
        I10_DX3 = dplyr::if_else(pick == 2L, "B5678", NA_character_),
        I10_PR1 = dplyr::if_else(pick == 1L, "02L73DK", "0JH60DZ")
      ) |>
      nis_flag_dx(
        one_prefix = "A12", several = c("A12", "B56", "C0"), position = "any"
      ) |>
      nis_flag_dx(first_slot = c("A1", "C004"), position = "principal") |>
      nis_flag_dx(late_slot = "B5", position = "secondary") |>
      nis_flag_pr(procedure = "02L", position = "any")
  }
  expected <- prepare_and_flag(data)
  lazy <- prepare_and_flag(query)
  expect_true(inherits(lazy, "arrow_dplyr_query"))
  actual <- dplyr::collect(lazy)

  expect_identical(actual, expected)
  expect_identical(actual$one_prefix, c(TRUE, TRUE, TRUE, FALSE, TRUE))
  expect_identical(actual$several, c(TRUE, TRUE, TRUE, TRUE, TRUE))
  expect_identical(actual$first_slot, c(TRUE, TRUE, TRUE, TRUE, TRUE))
  expect_identical(actual$late_slot, c(FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(actual$procedure, c(TRUE, FALSE, TRUE, FALSE, TRUE))
})

test_that("ICD-9 flags test only DX/PR slots and ICD-10 flags only I10_ slots", {
  malformed <- rawToChar(as.raw(c(0x34, 0x32, 0x38, 0xff)))
  data <- dplyr::tibble(
    DQTR = c(1L, 2L, 3L, 4L, 4L, 1L),
    DXVER = c(9L, 9L, 9L, 10L, 10L, 9L),
    DX1 = c("4280", "42823", "4869", NA, NA, malformed),
    DX2 = c("25000", "V667", "4280", NA, NA, "4281"),
    DXCCS1 = c("108", "108", "122", NA, NA, "108"),
    PR1 = c("3722", "8154", NA, NA, NA, "3722"),
    PR2 = c(NA, "3722", "3727", NA, NA, NA),
    PRDAY1 = c(1L, 2L, 3L, NA, NA, 1L),
    I10_DX1 = c(NA, NA, NA, "I5022", "J189", NA),
    I10_DX2 = c(NA, NA, NA, "E119", "I509", NA),
    I10_PR1 = c(NA, NA, NA, "02703ZZ", "0JH60DZ", NA)
  )
  data_path <- tempfile("nis-icd9-")
  dir.create(data_path)
  on.exit(unlink(data_path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(data_path, "part-0.parquet"))
  query <- arrow::open_dataset(data_path)

  add_flags <- function(.data) {
    .data |>
      nis_flag_dx(hf9 = "428", any_hf9 = c("4280", "4281", "V66"),
        system = "icd9") |>
      nis_flag_dx(principal9 = "428", system = "icd9", position = "principal") |>
      nis_flag_dx(secondary9 = "4 28", system = "icd9", position = "secondary") |>
      nis_flag_dx(hf10 = "I50") |>
      nis_flag_pr(proc9 = "37.2", system = "icd9") |>
      nis_flag_pr(first9 = "81", system = "icd9", position = "principal") |>
      nis_flag_pr(proc10 = "02703")
  }
  expected <- add_flags(data)
  lazy <- add_flags(query)
  expect_true(inherits(lazy, "arrow_dplyr_query"))
  actual <- dplyr::collect(lazy)
  expect_identical(actual, expected)

  expect_identical(actual$hf9, c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$any_hf9, c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$principal9, c(TRUE, TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_identical(actual$secondary9, c(FALSE, FALSE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$hf10, c(FALSE, FALSE, FALSE, TRUE, TRUE, FALSE))
  expect_identical(actual$proc9, c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$first9, c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(actual$proc10, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))
})

test_that("a prefix never crosses code systems in a mixed query", {
  data <- dplyr::tibble(
    DX1 = c("4280", NA),
    I10_DX1 = c(NA, "4280X")
  )
  flagged <- data |>
    nis_flag_dx(as_icd9 = "428", system = "icd9") |>
    nis_flag_dx(as_icd10 = "428")
  expect_identical(flagged$as_icd9, c(TRUE, FALSE))
  expect_identical(flagged$as_icd10, c(FALSE, TRUE))
})

test_that("version, year and 2015 quarter metadata prevent wrong-era matches", {
  data <- dplyr::tibble(
    YEAR = c(2012L, 2015L, 2015L, 2015L, 2015L, 2016L, 2015L, NA, 2015L),
    DQTR = c(4L, 1L, 4L, NA, 2L, 1L, 0L, NA, 4L),
    DXVER = c(9L, 9L, 10L, 10L, 10L, NA, NA, NA, 8L),
    PRVER = c(9L, 9L, 10L, 9L, 10L, NA, NA, NA, 8L),
    DX1 = "12345", DX30 = "V0001", PR15 = "0123",
    I10_DX1 = "A1234", I10_PR1 = "0AAAAAA"
  )
  add_flags <- function(.data) {
    .data |>
      nis_flag_dx(old = c("123", "V00"), system = "icd9") |>
      nis_flag_pr(old_proc = "012", system = "icd9") |>
      nis_flag_dx(new = "A12") |>
      nis_flag_pr(new_proc = "0AA")
  }
  actual <- add_flags(data)
  expect_identical(actual$old, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(actual$old_proc, c(TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(actual$new, c(FALSE, FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(actual$new_proc, c(FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(add_flags(arrow::arrow_table(data)) |> dplyr::collect(), actual)
  projected <- arrow::arrow_table(data) |> dplyr::mutate(DXVER = 10L)
  expect_false(any((add_flags(projected) |> dplyr::collect())$old))
})

test_that("invented 2015 split stays lazy across pooled years", {
  path <- nis_example(2012:2016)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  expect_message(query <- nis_open(path), "Experimental")
  lazy <- query |>
    nis_flag_dx(old = "123", system = "icd9") |>
    nis_flag_pr(old_proc = "012", system = "icd9") |>
    nis_flag_dx(new = "I50")
  expect_s3_class(lazy, "arrow_dplyr_query")
  data <- dplyr::collect(lazy)
  expect_setequal(data$YEAR, 2012:2016)
  expect_equal(nrow(data), 480L)
  expect_true(all(is.na(data$DX1[data$YEAR == 2015L & data$DQTR == 4L])))
  expect_true(all(is.na(data$I10_DX1[data$YEAR == 2015L & data$DQTR <= 3L])))
  expect_false(any(data$old[data$YEAR >= 2016L | (data$YEAR == 2015L & data$DQTR == 4L)]))
  expect_false(any(data$new[data$YEAR < 2015L | (data$YEAR == 2015L & data$DQTR <= 3L)]))
  expect_true(any(data$old[data$YEAR == 2015L]))
  expect_true(any(data$new[data$YEAR == 2015L]))
  expect_error(nis_example(2011), "2012 through 2024")
  expect_error(nis_example(Inf), "2012 through 2024")
})

test_that("missing slot columns for a code system give a system-specific error", {
  icd10_only <- dplyr::tibble(I10_DX1 = "I509", I10_PR1 = "02703ZZ")
  icd9_only <- dplyr::tibble(DX1 = "4280", PR1 = "3722", DXVER = 9L)
  expect_error(nis_flag_dx(icd10_only, x = "428", system = "icd9"), "ICD-9 DX columns")
  expect_error(nis_flag_pr(icd10_only, x = "37", system = "icd9"), "ICD-9 PR columns")
  expect_error(nis_flag_dx(icd9_only, x = "I50"), "ICD-10 DX columns")
  expect_error(nis_flag_dx(icd10_only, x = "I50", system = "icd8"), "should be one of")
})

test_that("nis_open accepts 2012 through 2015 and still rejects earlier years", {
  path <- nis_example(2012:2013)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  expect_message(query <- nis_open(path, years = 2012), "ICD-9")
  expect_true(all(c("DX1", "DX25", "PR15") %in% names(query)))
  expect_false(any(grepl("^I10_", names(query))))
  expect_error(nis_open(path, years = 2011), "before 2012")
  expect_error(nis_open(path, years = 2015), "No NIS Parquet entry")
})
