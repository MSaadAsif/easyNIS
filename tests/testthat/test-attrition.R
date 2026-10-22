test_that("nis_attrition reports ordered cumulative counts and drops", {
  toy_nis <- dplyr::tibble(
    AGE = c(16, 45, 60, 72, 55),
    ELECTIVE = c(1, 1, 0, 1, 1),
    DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
    YEAR = rep(2020L, 5)
  )

  result <- nis_attrition(toy_nis,
    adult = AGE >= 18,
    elective = ELECTIVE == 1
  )

  expect_identical(result$step, 0:2)
  expect_identical(result$criterion, c("All discharges", "adult", "elective"))
  expect_identical(result$n_unweighted, c(5L, 4L, 3L))
  expect_identical(result$n_dropped_unweighted, c(0L, 1L, 1L))
  expect_equal(result$n_weighted, c(25.1, 20.1, 15.3))
  expect_equal(result$n_dropped_weighted, c(0, 5, 4.8))
  expect_equal(result$pct_retained, c(100, 80, 60))
  expect_equal(result$n_unweighted[-1L] + result$n_dropped_unweighted[-1L],
    result$n_unweighted[-length(result$n_unweighted)])
  expect_equal(result$n_weighted[-1L] + result$n_dropped_weighted[-1L],
    result$n_weighted[-length(result$n_weighted)])

  unnamed <- nis_attrition(toy_nis, AGE >= 18)
  expect_identical(unnamed$criterion[[2L]], "AGE >= 18")
})

test_that("nis_attrition excludes missing criteria and handles zero cohorts", {
  data <- dplyr::tibble(
    include = c(TRUE, NA, FALSE),
    weight = c(2, NA, 5)
  )

  result <- nis_attrition(data, include, none = FALSE, weight_var = "weight")

  expect_identical(result$n_unweighted, c(3L, 1L, 0L))
  expect_identical(result$n_dropped_unweighted, c(0L, 2L, 1L))
  expect_equal(result$n_weighted, c(7, 2, 0))
  expect_equal(result$n_dropped_weighted, c(0, 5, 2))
  expect_identical(result$criterion, c("All discharges", "include", "none"))

  empty <- nis_attrition(data, none = FALSE, after = FALSE, weight_var = "weight")
  expect_equal(empty$n_unweighted, c(3L, 0L, 0L))
  expect_equal(empty$pct_retained, c(100, 0, 0))
  zero <- nis_attrition(data[FALSE, ], none = FALSE, weight_var = "weight")
  expect_true(all(is.na(zero$pct_retained)))
})

test_that("nis_attrition stratifies by year and preserves overall totals", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L, 2021L),
    keep = c(TRUE, FALSE, TRUE, NA, FALSE),
    DISCWT = c(2, 3, 5, 7, 11)
  )
  overall <- nis_attrition(data, keep)
  annual <- nis_attrition(data, keep, by_year = TRUE)

  expect_identical(names(annual)[[1L]], "YEAR")
  expect_equal(annual$YEAR, c(2020L, 2020L, 2021L, 2021L))
  expect_equal(annual$step, c(0L, 1L, 0L, 1L))
  expect_equal(sum(annual$n_unweighted[annual$step == 0L]), overall$n_unweighted[[1L]])
  expect_equal(sum(annual$n_unweighted[annual$step == 1L]), overall$n_unweighted[[2L]])
  expect_equal(sum(annual$n_weighted[annual$step == 0L]), overall$n_weighted[[1L]])
  expect_equal(sum(annual$n_weighted[annual$step == 1L]), overall$n_weighted[[2L]])
  expect_error(nis_attrition(data["keep"], keep, by_year = TRUE), "YEAR")
  expect_error(nis_attrition(dplyr::mutate(data, YEAR = NA_integer_), keep,
    by_year = TRUE), "YEAR")
})

test_that("nis_attrition lazily aggregates DuckDB datasets without collecting rows", {
  data <- dplyr::tibble(
    AGE = c(16, 45, 60, 72, 55),
    ELECTIVE = c(1, 1, 0, 1, 1),
    DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
    YEAR = c(2020L, 2020L, 2020L, 2021L, 2021L),
    .nis_attrition_keep_1 = seq_len(5L)
  )
  path <- tempfile("nis-attrition-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)
  criteria <- function(.data) {
    nis_attrition(
      .data,
      adult = AGE >= 18,
      elective = ELECTIVE == 1
    )
  }

  actual <- criteria(query)
  expect_s3_class(actual, "tbl_df")
  expect_identical(actual, criteria(data))

  annual <- nis_attrition(query, adult = AGE >= 18, by_year = TRUE)
  expect_identical(annual, nis_attrition(data, adult = AGE >= 18, by_year = TRUE))
})

test_that("nis_attrition validates criteria and weights", {
  data <- dplyr::tibble(DISCWT = 1)
  expect_error(nis_attrition(data), "at least one")
  expect_error(nis_attrition(data, TRUE, weight_var = "MISSING"), "MISSING")
  expect_error(nis_attrition(data, TRUE, by_year = NA), "`by_year`")
  expect_error(nis_attrition(data, TRUE, by_year = c(TRUE, FALSE)), "`by_year`")
  expect_error(nis_attrition(data, TRUE, weight_var = NA_character_), "`weight_var`")
  expect_error(nis_attrition(data, TRUE, weight_var = c("DISCWT", "other")), "`weight_var`")
  expect_error(nis_attrition(data, TRUE, by_year = TRUE), "YEAR")
})

test_that("nis_attrition returns an empty annual summary for empty input", {
  data <- dplyr::tibble(YEAR = integer(), weight = double(), keep = logical())
  result <- nis_attrition(data, keep, by_year = TRUE, weight_var = "weight")

  expect_named(result, c("YEAR", "step", "criterion", "n_unweighted",
    "n_dropped_unweighted", "n_weighted", "n_dropped_weighted", "pct_retained"))
  expect_equal(nrow(result), 0L)
  expect_type(result$YEAR, "integer")
  expect_type(result$n_unweighted, "integer")
  expect_type(result$n_weighted, "double")
  expect_type(result$pct_retained, "double")
})
