test_that("code transition audit completes the period and code-group grid", {
  data <- dplyr::tibble(
    YEAR = c(2018L, 2018L, 2019L, 2019L, 2020L, 2020L),
    I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02803ZZ", "02803ZZ", "02803ZZ"),
    I10_PR2 = c("02UG0JZ", NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
    DISCWT = c(5, 7, 5, 3, 4, 6),
    AGE = c(40L, 17L, 60L, 50L, 70L, 45L)
  )
  result <- nis_audit_code_transition(data,
    codes = c(myectomy = "02UG0JZ", ablation = "02803ZZ"))

  expect_named(result, c("YEAR", "code_group", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "pct_within_year", "yoy_pct_change"))
  expect_equal(nrow(result), 6L)
  expect_equal(result$code_group,
    c(rep("myectomy", 3), rep("ablation", 3)))
  expect_equal(result$n_cohort_unweighted, rep(2L, 6))
  expect_equal(result$n_unweighted, c(2L, 1L, 0L, 0L, 1L, 2L))
  expect_equal(result$n_weighted, c(12, 5, 0, 0, 3, 10))
  expect_equal(result$pct_within_year, c(100, 50, 0, 0, 50, 100))
  expect_true(is.na(result$yoy_pct_change[[1L]]))
  expect_equal(result$yoy_pct_change[[2L]], -50)
  expect_equal(result$yoy_pct_change[[3L]], -100)
  expect_true(is.na(result$yoy_pct_change[[5L]]))
  expect_equal(result$yoy_pct_change[[6L]], 100)
})

test_that("code transition audit filters the cohort before counting", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2020L, 2021L),
    I10_DX1 = c("I501", "I502", "I501", "J189"),
    DISCWT = c(2, 3, 7, 5),
    AGE = c(30L, 17L, NA_integer_, 40L)
  )
  result <- nis_audit_code_transition(data, list(hf = c("I50")),
    cohort = AGE >= 18, type = "dx")

  expect_equal(result$n_cohort_unweighted, c(1L, 1L))
  expect_equal(result$n_unweighted, c(1L, 0L))
  expect_equal(result$n_weighted, c(2, 0))
})

test_that("code transition audit agrees between data frames and lazy DuckDB", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L, 2020L),
    I10_PR1 = c("02UG0JZ", "02803ZZ", "02803ZZ", NA_character_),
    I10_DX1 = c("I509", "J189", "I50", "I501"),
    I10_PR2 = c("02UG0JZ", NA_character_, NA_character_, NA_character_),
    DISCWT = c(5, 4, 7, 2),
    AGE = c(40L, 50L, 60L, 16L)
  )
  path <- tempfile("nis-audit-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)
  codes <- list(myectomy = "02UG0JZ", ablation = "02803ZZ")

  from_frame <- nis_audit_code_transition(data, codes, cohort = AGE >= 18)
  from_DuckDB <- nis_audit_code_transition(query, codes, cohort = AGE >= 18)
  from_frame_dx <- nis_audit_code_transition(data, list(hf = "I50"),
    cohort = AGE >= 18, type = "dx")
  from_DuckDB_dx <- nis_audit_code_transition(query, list(hf = "I50"),
    cohort = AGE >= 18, type = "dx")

  expect_identical(from_DuckDB, from_frame)
  expect_identical(from_DuckDB_dx, from_frame_dx)
})

test_that("code transition audit validates named groups and columns", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)
  expect_error(nis_audit_code_transition(data, c("02UG0JZ")), "named")
  duplicate_codes <- c("02UG0JZ", "02UG0JZ")
  names(duplicate_codes) <- c("a", "a")
  expect_error(nis_audit_code_transition(data, duplicate_codes), "unique")
  expect_error(nis_audit_code_transition(data, list(a = NA_character_)), "non-missing")
  data$n_unweighted <- 1L
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"),
    by = "n_unweighted"), "summary column")
})

test_that("code transition audit validates periods, weights, and every code group", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)

  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), by = NA_character_), "`by`")
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), by = "MISSING"), "`by`")
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), weight_var = "MISSING"),
    "`weight_var`")
  expect_error(nis_audit_code_transition(data, list(a = character())), "non-missing character")
  expect_error(nis_audit_code_transition(data, list(a = 1)), "non-missing character")
  expect_error(nis_audit_code_transition(data, list(a = c("02UG", NA_character_))),
    "non-missing character")
})

test_that("code transition audit avoids temporary names in user data", {
  data <- dplyr::tibble(
    .nis_audit_cohort = c(2020L, 2020L),
    .nis_audit_flag_1 = c("occupied", "occupied"),
    .nis_audit_n_1 = c(10L, 20L),
    .nis_audit_w_1 = c(1, 2),
    I10_PR1 = c("02UG0JZ", NA_character_),
    DISCWT = c(3, 4)
  )

  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"),
    by = ".nis_audit_cohort")

  expect_equal(result$n_cohort_unweighted, 2L)
  expect_equal(result$n_unweighted, 1L)
  expect_equal(result$n_weighted, 3)
})

test_that("code transition audit returns the empty grid for an empty cohort", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)
  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"),
    cohort = FALSE)

  expect_equal(nrow(result), 0L)
  expect_named(result, c("YEAR", "code_group", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "pct_within_year", "yoy_pct_change"))

  path <- tempfile("nis-audit-empty-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  from_DuckDB <- nis_audit_code_transition(open_duckdb_dataset(path),
    c(myectomy = "02UG0JZ"), cohort = FALSE)
  expect_identical(from_DuckDB, result)
})

test_that("missing periods have no year-over-year percentage change", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2020L, NA_integer_),
    I10_PR1 = c("02UG0JZ", NA_character_, "02UG0JZ"),
    DISCWT = c(1, 1, 1)
  )
  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"))

  expect_true(is.na(result$yoy_pct_change[[3L]]))
})
