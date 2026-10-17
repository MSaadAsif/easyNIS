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

test_that("2023 layout opens without optional geography and keeps year-scoped IDs", {
  path <- tempfile("nis-2023-layout-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  year_2022 <- file.path(path, "NIS_2022.parquet")
  year_2023 <- file.path(path, "NIS_2023.parquet")
  dir.create(year_2022)
  dir.create(year_2023)
  data_2022 <- dplyr::tibble(
    YEAR = rep(2022L, 2L), HOSP_NIS = 101:102, NIS_STRATUM = c(1L, 1L),
    DISCWT = c(1, 1), eligible = c(TRUE, TRUE), AGE = c(50, 60),
    TOTCHG = c(1000, 1100), CCR_NIS = c(0.25, 0.25),
    HOSP_REGION = c(1L, 1L), HOSP_DIVISION = c(1L, 1L), RACE = c(1L, 2L)
  )
  data_2023 <- dplyr::tibble(
    YEAR = rep(2023L, 2L), HOSP_NIS = 101:102, NIS_STRATUM = c(1L, 1L),
    DISCWT = c(1, 1), eligible = c(TRUE, TRUE), AGE = c(70, 80),
    TOTCHG_2023 = c(2000, 2200), CCR_NIS = c(0.25, 0.25), PL_NCHS2 = c(21L, 22L)
  )
  arrow::write_parquet(data_2022, file.path(year_2022, "part-0.parquet"))
  arrow::write_parquet(data_2023, file.path(year_2023, "part-0.parquet"))

  rlang::reset_warning_verbosity("easyNIS_totchg_2023")
  expect_warning(
    latest <- nis_open(path, years = 2023L),
    "not comparable"
  )
  expect_no_warning(nis_open(path, years = 2023L))
  expect_true(inherits(latest, "arrow_dplyr_query"))
  expect_false(any(c("HOSP_REGION", "HOSP_DIVISION", "RACE") %in% names(latest)))
  expect_true("TOTCHG_2023" %in% names(latest))
  expect_false("TOTCHG" %in% names(latest))

  pooled_query <- suppressWarnings(nis_open(path, years = 2022:2023))
  collected <- dplyr::collect(pooled_query)
  expect_identical(collected$TOTCHG[order(collected$YEAR, collected$HOSP_NIS)],
    c(1000, 1100, NA, NA))
  expect_identical(
    collected$TOTCHG_2023[order(collected$YEAR, collected$HOSP_NIS)],
    c(NA, NA, 2000, 2200)
  )

  # 2023 charges require an explicit opt-in; TOTCHG alone has no 2023 values.
  expect_error(
    nis_design(latest, eligible, keep = c(AGE, TOTCHG_2023, CCR_NIS), dollars = 2023),
    "TOTCHG"
  )
  latest_design <- latest |>
    nis_design(eligible, keep = c(AGE, TOTCHG_2023, CCR_NIS), dollars = 2023,
      charges = "TOTCHG_2023")
  expect_equal(nrow(latest_design$variables), 2L)
  expect_equal(sort(latest_design$variables$cost_adj), c(500, 550))

  # Default pooled design uses TOTCHG only: 2023 rows stay missing.
  default_pool <- pooled_query |>
    nis_design(eligible, keep = c(AGE, TOTCHG, CCR_NIS), dollars = 2023)
  variables <- default_pool$variables
  order_rows <- order(variables$YEAR, variables$HOSP_NIS)
  expect_false("TOTCHG_2023" %in% names(variables))
  expect_true(all(is.na(variables$cost_adj[variables$YEAR == 2023L])))
  expect_true(all(is.finite(variables$cost_adj[variables$YEAR == 2022L])))
  expect_setequal(variables$.nis_psu,
    c("2022::101", "2022::102", "2023::101", "2023::102"))
  expect_setequal(variables$.nis_stratum, c("2022::1", "2023::1"))

  # An analyst may pool charge definitions with one explicit mutate.
  explicit <- pooled_query |>
    dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG)) |>
    nis_design(eligible, keep = c(AGE, TOTCHG, CCR_NIS), dollars = 2023)
  explicit_vars <- explicit$variables
  expect_equal(
    explicit_vars$TOTCHG[order(explicit_vars$YEAR, explicit_vars$HOSP_NIS)],
    c(1000, 1100, 2000, 2200)
  )
  expect_true(all(is.finite(explicit_vars$cost_adj)))
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
