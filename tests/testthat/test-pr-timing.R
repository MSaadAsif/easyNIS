test_that("procedure timing evaluates every relation and the earliest index day", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "IX", "IX"),
    I10_PR2 = c("IX", "IX", "IX", "IX", "IX", "IX"),
    I10_PR3 = c("OUT", "OUT", "OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(3L, 3L, 3L, 3L, 3L, 3L),
    PRDAY2 = c(1L, 1L, 1L, 1L, 1L, 1L),
    PRDAY3 = c(2L, 4L, 1L, 1L, 6L, 0L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "on_or_after")$outcome_post_index,
    c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "after")$outcome_post_index,
    c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "before")$outcome_post_index,
    c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "same_day")$outcome_post_index,
    c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "within_days",
      window = 1L)$outcome_post_index,
    c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "ix", "out", relation = "within_days"),
    "window")
  expect_error(nis_flag_pr_timing(data, "ix", "out", window = 1L), "NULL")
})

test_that("procedure timing matches the documented four-row example", {
  data <- dplyr::tibble(
    I10_PR1 = rep("02UG0JZ", 4L),
    PRDAY1 = c(0L, 2L, 3L, -99L),
    I10_PR2 = rep("0JH604Z", 4L),
    PRDAY2 = c(1L, 1L, 3L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "02UG0", "0JH60")$outcome_post_index,
    c(TRUE, FALSE, TRUE, FALSE)
  )
})

test_that("procedure timing handles missing days and absent procedures", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "OTHER", "IX"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT", "OUT", "OTHER"),
    PRDAY1 = c(-99L, NA_integer_, 0L, -99L, 1L, 0L),
    PRDAY2 = c(1L, 1L, -88L, -66L, 2L, 1L)
  )
  for (policy in c("exclude", "assume_same_day", "indeterminate")) {
    actual <- nis_flag_pr_timing(data, "IX", "OUT", missing_day = policy)$outcome_post_index
    expected <- switch(policy,
      exclude = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
      assume_same_day = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
      indeterminate = c(NA, NA, NA, NA, FALSE, FALSE)
    )
    expect_identical(actual, expected)
  }
  # A determinate satisfying pair wins even if another matching slot is unknown.
  mixed <- dplyr::tibble(I10_PR1 = "IX", I10_PR2 = c("IX", "OUT"),
    I10_PR3 = c("OUT", "IX"), PRDAY1 = c(-99L, 0L),
    PRDAY2 = c(0L, 0L), PRDAY3 = c(0L, -99L))
  expect_identical(
    nis_flag_pr_timing(mixed, "IX", "OUT", missing_day = "indeterminate")$outcome_post_index,
    c(TRUE, TRUE)
  )
})

test_that("procedure timing uses ICD-9 slots and validates its output", {
  data <- dplyr::tibble(
    PR1 = c("3722", "3722"), PR2 = c("3325", "3325"),
    PRDAY1 = c(1L, 3L), PRDAY2 = c(2L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "37.2", "33 25", system = "icd9")$outcome_post_index,
    c(TRUE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "37", "33", name = "PR1"),
    "must not replace")
  expect_error(nis_flag_pr_timing(dplyr::select(data, -PRDAY1, -PRDAY2),
    "37", "33", system = "icd9"), "PRDAY")
  expect_error(nis_flag_pr_timing(data, "37", "33", name = c("x", "y")),
    "single")
})

test_that("procedure timing stays lazy and agrees with data frames on Arrow", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "OTHER"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(0L, 2L, -99L, 1L), PRDAY2 = c(1L, 1L, 1L, 2L)
  )
  path <- tempfile("nis-pr-timing-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(path, "part-0.parquet"))
  query <- arrow::open_dataset(path)
  expected <- nis_flag_pr_timing(data, "IX", "OUT")
  lazy <- nis_flag_pr_timing(query, "IX", "OUT")
  expect_s3_class(lazy, "arrow_dplyr_query")
  expect_identical(dplyr::collect(lazy), expected)
})
