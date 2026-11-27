test_that("nis_open validation errors retain their public call", {
  condition <- tryCatch(nis_open(tempfile(), years = 2018L), error = identity)

  expect_s3_class(condition, "rlang_error")
  expect_identical(as.character(conditionCall(condition)[[1L]]), "nis_open")
})

test_that("nis_open stays lazy and unifies the 2022 APR-DRG case drift", {
  path <- nis_example(2017:2022)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  query <- nis_open(path)
  expect_true(inherits(query, "tbl_sql"))
  expect_true("APRDRG_RISK_MORTALITY" %in% colnames(query))
  expect_false(any(grepl("^APRDRG_Risk_Mortality$", colnames(query))))

  aprdrg <- query |>
    dplyr::select(YEAR, APRDRG_RISK_MORTALITY) |>
    dplyr::collect()
  expect_equal(nrow(aprdrg), 576L)
  expect_true(all(aprdrg$APRDRG_RISK_MORTALITY[aprdrg$YEAR == 2022] %in% 0:4))
  expect_true(all(aprdrg$APRDRG_RISK_MORTALITY[aprdrg$YEAR < 2022] %in% 0:4))
  expect_error(nis_open(path, years = 2015), "No NIS Parquet entry")
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
    YEAR = rep(2022L, 2L),
    HOSP_NIS = 101:102,
    NIS_STRATUM = c(1L, 1L),
    DISCWT = c(1, 1),
    eligible = c(TRUE, TRUE),
    AGE = c(50, 60),
    TOTCHG = c(1000, 1100),
    CCR_NIS = c(0.25, 0.25),
    HOSP_REGION = c(1L, 1L),
    HOSP_DIVISION = c(1L, 1L),
    RACE = c(1L, 2L)
  )
  data_2023 <- dplyr::tibble(
    YEAR = rep(2023L, 2L),
    HOSP_NIS = 101:102,
    NIS_STRATUM = c(1L, 1L),
    DISCWT = c(1, 1),
    eligible = c(TRUE, TRUE),
    AGE = c(70, 80),
    TOTCHG_2023 = c(2000, 2200),
    CCR_NIS = c(0.25, 0.25),
    PL_NCHS2 = c(21L, 22L)
  )
  write_duckdb_parquet(data_2022, file.path(year_2022, "part-0.parquet"))
  write_duckdb_parquet(data_2023, file.path(year_2023, "part-0.parquet"))

  rlang::reset_warning_verbosity("easyNIS_totchg_2023")
  expect_warning(
    latest <- nis_open(path, years = 2023L, check_release = FALSE),
    "not comparable"
  )
  expect_no_warning(nis_open(path, years = 2023L, check_release = FALSE))
  expect_true(inherits(latest, "tbl_sql"))
  expect_false(any(c("HOSP_REGION", "HOSP_DIVISION", "RACE") %in% colnames(latest)))
  expect_true("TOTCHG_2023" %in% colnames(latest))
  expect_false("TOTCHG" %in% colnames(latest))

  pooled_query <- nis_open(path, years = 2022:2023, check_release = FALSE)
  collected <- dplyr::collect(pooled_query)
  expect_identical(collected$TOTCHG[order(collected$YEAR, collected$HOSP_NIS)], c(1000, 1100, NA, NA))
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
    nis_design(eligible, keep = c(AGE, TOTCHG_2023, CCR_NIS), dollars = 2023, charges = "TOTCHG_2023")
  expect_equal(nrow(latest_design$variables), 2L)
  expect_equal(sort(latest_design$variables$cost_adj), c(500, 550))

  # Default pooled design uses TOTCHG only: 2023 rows stay missing.
  expect_warning(
    default_pool <- pooled_query |>
      nis_design(eligible, keep = c(AGE, TOTCHG, CCR_NIS), dollars = 2023),
    "TOTCHG.*entirely missing in some cohort years"
  )
  variables <- default_pool$variables
  order_rows <- order(variables$YEAR, variables$HOSP_NIS)
  expect_false("TOTCHG_2023" %in% names(variables))
  expect_true(all(is.na(variables$cost_adj[variables$YEAR == 2023L])))
  expect_true(all(is.finite(variables$cost_adj[variables$YEAR == 2022L])))
  expect_setequal(
    as.character(default_pool$cluster[[1L]]),
    c("2022::1.2022::101", "2022::1.2022::102", "2023::1.2023::101", "2023::1.2023::102")
  )
  expect_setequal(as.character(default_pool$strata[[1L]]), c("2022::1", "2023::1"))

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

test_that("nis_open accepts 2012 through 2015 and still rejects earlier years", {
  path <- nis_example(2012:2013)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  rlang::reset_message_verbosity("easyNIS_icd9_layout")
  withr::defer(rlang::reset_message_verbosity("easyNIS_icd9_layout"))
  expect_message(query <- nis_open(path, years = 2012), "ICD-9")
  expect_true(all(c("DX1", "DX25", "PR15") %in% colnames(query)))
  expect_false(any(grepl("^I10_", colnames(query))))
  expect_error(nis_open(path, years = 2011), "before 2012")
  expect_error(nis_open(path, years = 2015), "No NIS Parquet entry")
})

test_that("nis_open validation errors retain the full public call", {
  path <- tempfile("nis-open-invalid-years-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  condition <- tryCatch(nis_open(path, years = 2011L), error = identity)

  expect_s3_class(condition, "rlang_error")
  expect_identical(conditionCall(condition), quote(nis_open(path, years = 2011L)))
})

test_that("nis_open source errors retain the full public call", {
  path <- tempfile("nis-open-empty-hive-")
  dir.create(file.path(path, "YEAR=2012"), recursive = TRUE)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  condition <- tryCatch(nis_open(path, years = 2012L), error = identity)

  expect_s3_class(condition, "rlang_error")
  expect_match(conditionMessage(condition), "no Parquet part files")
  expect_identical(conditionCall(condition), quote(nis_open(path, years = 2012L)))
})

test_that("year arguments outside R's integer range are rejected without coercion warnings", {
  path <- tempfile("nis-open-year-range-")
  dir.create(file.path(path, "NIS_2020.parquet"), recursive = TRUE)
  withr::defer(unlink(path, recursive = TRUE))

  expect_no_warning(expect_error(nis_open(path, years = .Machine$integer.max + 1), "non-empty vector of whole years"))
})
