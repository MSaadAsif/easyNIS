test_that("attrition ignores input groups for criteria and aggregate totals", {
  data <- dplyr::tibble(
    YEAR = rep(2020:2021, each = 3L),
    group = rep(c("a", "b"), 3L),
    score = 1:6,
    keep = c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE),
    DISCWT = c(2, NA_real_, NaN, 3, 5, 7)
  )
  query <- duckdb_query_fixture(data)
  local_sql_na_warnings()

  # Rows 1, 2, 4, 6 pass keep; only rows 4 and 6 also exceed 3.5.
  for (grouped in list(data, query, dplyr::rowwise(data),
    dplyr::group_by(data, YEAR, group), dplyr::group_by(query, YEAR, group))) {
    result <- nis_attrition(grouped, keep, above_mean = score >= mean(score, na.rm = TRUE))
    expect_identical(result$n_unweighted, c(6L, 4L, 2L))
    expect_equal(result$n_dropped_unweighted, c(NA, 2, 2))
    expect_equal(result$n_weighted, c(17, 12, 10))
    expect_equal(result$n_dropped_weighted, c(NA, 5, 2))
    expect_equal(result$pct_retained, 100 * c(1, 4 / 6, 2 / 6))

    annual <- nis_attrition(grouped, keep, above_mean = score >= mean(score, na.rm = TRUE),
      by_year = TRUE)
    expect_equal(annual$YEAR, rep(2020:2021, each = 3L))
    expect_identical(annual$step, rep(0:2, 2L))
    expect_identical(annual$n_unweighted, c(3L, 2L, 0L, 3L, 2L, 2L))
    expect_equal(annual$n_dropped_unweighted, c(NA, 1, 2, NA, 1, 0))
    expect_equal(annual$n_weighted, c(2, 2, 0, 15, 10, 10))
    expect_equal(annual$n_dropped_weighted, c(NA, 0, 2, NA, 5, 0))
    expect_equal(annual$pct_retained, 100 * c(1, 2 / 3, 0, 1, 2 / 3, 2 / 3))
  }
})

test_that("missing logical criteria and logical weights agree across backends", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L),
    keep = c(TRUE, NA, TRUE, FALSE),
    weight = c(TRUE, TRUE, NA, FALSE),
    unknown = rep(NA, 4L)
  )
  query <- duckdb_query_fixture(data)
  local_sql_na_warnings()

  # Only rows 1 and 3 pass keep; row 3 has zero weight. No row passes unknown.
  for (input in list(data, dplyr::rowwise(data), query)) {
    result <- nis_attrition(input, keep, unknown, weight_var = "weight")
    expect_identical(result$n_unweighted, c(4L, 2L, 0L))
    expect_equal(result$n_weighted, c(2, 1, 0))
    expect_equal(result$n_dropped_weighted, c(NA, 1, 1))
    annual <- nis_attrition(input, keep, unknown, by_year = TRUE,
      weight_var = "weight")
    expect_equal(annual$YEAR, rep(2020:2021, each = 3L))
    expect_identical(annual$n_unweighted, c(2L, 1L, 0L, 2L, 1L, 0L))
    expect_equal(annual$n_weighted, c(2, 1, 0, 0, 0, 0))

    missing <- dplyr::mutate(input, weight = NA)
    expect_equal(nis_attrition(missing, keep, weight_var = "weight")$n_weighted,
      c(0, 0))
  }
})

test_that("empty attrition totals are zero and empty annual output has no rows", {
  data <- dplyr::tibble(YEAR = 2020L, group = "a", DISCWT = 2, keep = TRUE)
  query <- duckdb_query_fixture(data)
  local_sql_na_warnings()

  for (input in list(data, query)) {
    grouped <- input |> dplyr::filter(FALSE) |> dplyr::group_by(YEAR, group)
    result <- nis_attrition(grouped, keep, second = keep)
    expect_identical(result$n_unweighted, c(0L, 0L, 0L))
    expect_equal(result$n_weighted, c(0, 0, 0))
    expect_equal(result$n_dropped_unweighted, c(NA, 0, 0))
    expect_equal(result$n_dropped_weighted, c(NA, 0, 0))
    expect_equal(result$pct_retained, rep(NA_real_, 3L))

    annual <- nis_attrition(grouped, keep, second = keep, by_year = TRUE)
    expect_equal(nrow(annual), 0L)
    expect_named(annual, c("YEAR", "step", "criterion", "n_unweighted",
      "n_dropped_unweighted", "n_weighted", "n_dropped_weighted", "pct_retained"))
    expect_type(annual$YEAR, "integer")
    expect_type(annual$n_unweighted, "integer")
    expect_type(annual$n_weighted, "double")
  }
})

test_that("missing weights contribute zero while infinite weights are retained", {
  data <- dplyr::tibble(
    DISCWT = c(NA_real_, NaN, Inf, -Inf),
    keep = c(TRUE, TRUE, TRUE, FALSE),
    missing_only = c(TRUE, TRUE, FALSE, FALSE)
  )
  query <- duckdb_query_fixture(data)
  local_sql_na_warnings()

  for (input in list(data, query)) {
    result <- nis_attrition(input, keep, missing_only)
    expect_identical(result$n_unweighted, c(4L, 3L, 2L))
    expect_true(is.nan(result$n_weighted[[1L]]))
    expect_equal(result$n_weighted[-1L], c(Inf, 0))
    expect_true(is.na(result$n_dropped_weighted[[1L]]))
    expect_true(is.nan(result$n_dropped_weighted[[2L]]))
    expect_equal(result$n_dropped_weighted[[3L]], Inf)
  }
})


test_that("attrition preserves counts from a DuckDB integer64 connection", {
  skip_if_not_installed("bit64")
  frame <- dplyr::tibble(YEAR = rep(2020:2021, each = 3L), DISCWT = 1,
    include = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE))
  con <- DBI::dbConnect(duckdb::duckdb(bigint = "integer64"))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  query <- dplyr::copy_to(con, frame, "invented_attrition64", temporary = TRUE)

  expected <- nis_attrition(frame, include, by_year = TRUE)
  expect_identical(nis_attrition(query, include, by_year = TRUE), expected)
})


test_that("attrition summary aliases cannot shadow the selected weight", {
  frame <- dplyr::tibble(age = c(17, 18, 19), .nis_attrition_w_0 = c(1, 2, 3))
  for (data in list(frame, duckdb_query_fixture(frame))) {
    result <- nis_attrition(data, adults = age >= 18, weight_var = ".nis_attrition_w_0")
    expect_identical(result$n_weighted, c(6, 5))
    expect_identical(result$n_dropped_weighted, c(NA_real_, 1))
  }
})
