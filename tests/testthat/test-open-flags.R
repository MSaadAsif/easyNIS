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
  expect_error(nis_open(path, years = 2015), "ICD-9")
  expect_error(nis_open(path, years = 2011), "before 2012")
})

test_that("ICD flags match prefixes by slot and behave the same on Arrow", {
  data <- dplyr::tibble(
    I10_DX1 = c("i50.90", "J18.9", "I5", NA_character_, "E11.9"),
    I10_DX2 = c("J18.9", "I50 22", "0", "I50.1", "I50.9"),
    I10_DX3 = c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
    I10_PR1 = c("02L73DK", "0JH60DZ", NA_character_, "02703ZZ", "02. L73D K"),
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
      nis_flag_pr(any_proc = "02L", position = "any") |>
      nis_flag_pr(principal_proc = "02.L", position = "principal")
  }
  expected <- add_flags(data)
  actual <- add_flags(query) |> dplyr::collect()

  expect_identical(actual, expected)
  expect_identical(actual$any_hf, c(TRUE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(actual$principal_hf, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(actual$secondary_hf, c(FALSE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(actual$any_proc, c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(actual$principal_proc, c(TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_error(nis_flag_dx(data, invalid = "I50-"), "letters and numbers")
  expect_error(nis_flag_dx(data, invalid = "I50", invalid = "I51"), "unique")
})

test_that("ICD flags treat malformed UTF-8 and non-code text as non-matching", {
  malformed <- rawToChar(as.raw(c(0x49, 0x35, 0x30, 0xff, 0xfe)))
  data <- dplyr::tibble(
    I10_DX1 = c("I50.9", malformed, NA_character_, "z515", "I\t5 0", "I50\u00e9", "E11"),
    I10_DX2 = c(NA_character_, "J18", "Z 51.5", malformed, NA_character_, "I51", "I5")
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

  expect_identical(actual$any_hf, c(TRUE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE))
  expect_identical(actual$palliative, c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(actual$principal_hf, c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(suppressWarnings(add_flags(data)), actual)
})
