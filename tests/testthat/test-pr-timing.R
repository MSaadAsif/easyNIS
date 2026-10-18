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
  expect_error(nis_flag_pr_timing(data, NA_character_, "out"), "index_pr")
  expect_error(nis_flag_pr_timing(data, "ix", NA_character_), "outcome_pr")
  expect_error(nis_flag_pr_timing(data, "ix", "out-"), "letters and numbers")
})

test_that("procedure timing accepts integer and mixed numeric day columns", {
  integer_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L), PRDAY2 = c(1L, 1L)
  )
  expect_identical(
    nis_flag_pr_timing(integer_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )

  mixed_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L), PRDAY2 = c(1, 1)
  )
  expect_identical(
    nis_flag_pr_timing(mixed_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )
})

test_that("procedure timing treats an unmatched PRDAY slot as unknown", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "IX", "OUT")$outcome_post_index,
    c(FALSE, FALSE)
  )
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

test_that("procedure timing policies have explicit relation expectations", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "IX"),
    I10_PR2 = c("OTHER", "OTHER", "IX", "OTHER", "OTHER"),
    I10_PR3 = rep("OUT", 5L),
    PRDAY1 = c(5L, -99L, -99L, 5L, 5L),
    PRDAY2 = c(1L, 1L, 5L, 1L, 1L),
    PRDAY3 = c(NA_real_, 0, 4, 3, 5)
  )
  expected <- list(
    exclude = list(
      on_or_after = c(FALSE, FALSE, FALSE, FALSE, TRUE),
      after = c(FALSE, FALSE, FALSE, FALSE, FALSE),
      before = c(FALSE, FALSE, TRUE, TRUE, FALSE),
      same_day = c(FALSE, FALSE, FALSE, FALSE, TRUE),
      within_days = c(FALSE, FALSE, FALSE, FALSE, TRUE)
    ),
    assume_same_day = list(
      on_or_after = c(FALSE, TRUE, TRUE, FALSE, TRUE),
      after = c(FALSE, FALSE, TRUE, FALSE, FALSE),
      before = c(TRUE, FALSE, FALSE, TRUE, FALSE),
      same_day = c(FALSE, TRUE, FALSE, FALSE, TRUE),
      within_days = c(FALSE, TRUE, FALSE, FALSE, TRUE)
    ),
    indeterminate = list(
      on_or_after = c(NA, NA, NA, FALSE, TRUE),
      after = c(NA, NA, NA, FALSE, FALSE),
      before = c(NA, NA, TRUE, TRUE, FALSE),
      same_day = c(NA, NA, NA, FALSE, TRUE),
      within_days = c(NA, NA, NA, FALSE, TRUE)
    )
  )
  for (policy in names(expected)) {
    for (relation in names(expected[[policy]])) {
      window <- if (relation == "within_days") 1L else NULL
      expect_identical(
        nis_flag_pr_timing(data, "IX", "OUT", relation = relation,
          window = window, missing_day = policy)$outcome_post_index,
        expected[[policy]][[relation]],
        info = paste(policy, relation)
      )
    }
  }
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

test_that("procedure timing agrees across Arrow policies and many slots", {
  procedure_slots <- stats::setNames(rep(list(rep("OTHER", 5L)), 25L),
    paste0("I10_PR", seq_len(25L)))
  procedure_slots[[1L]] <- c("IX", "IX", "IX", "IX", "IX")
  procedure_slots[[2L]] <- c("OUT", "OUT", "OUT", "OUT", "OUT")
  procedure_slots[[3L]] <- c("IDX", "IDX", "OTHER", "OTHER", "OTHER")
  procedure_slots[[4L]] <- c("ALT", "ALT", "ALT", "ALT", "ALT")
  procedure_slots[[12L]] <- c("OUT", "OUT", "OUT", "OUT", "OUT")
  day_slots <- stats::setNames(rep(list(rep(1L, 5L)), 11L),
    paste0("PRDAY", seq_len(11L)))
  day_slots[[1L]] <- c(0L, -99L, 0L, -99L, -99L)
  day_slots[[2L]] <- c(1, 1, -99, NA_real_, 1)
  day_slots[[3L]] <- c(2L, 1L, 0L, -99L, 1L)
  day_slots[[4L]] <- c(3L, -99L, 0L, 1L, 1L)
  data <- dplyr::as_tibble(c(procedure_slots, day_slots, list(
    YEAR = rep(2018L, 5L), PRVER = c(10L, 10L, 10L, 10L, 9L)
  )))
  path <- tempfile("nis-pr-timing-many-slots-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(path, "part-0.parquet"))
  query <- arrow::open_dataset(path)

  small_data <- dplyr::select(data, I10_PR1:I10_PR4, PRDAY1:PRDAY4, YEAR, PRVER)
  small_query <- arrow::arrow_table(small_data)
  query_data <- list(list(data, query), list(small_data, small_query))
  for (i in seq_along(query_data)) {
    cases <- if (i == 1L) {
      list(c("exclude", "on_or_after"), c("indeterminate", "on_or_after"),
        c("indeterminate", "within_days"))
    } else {
      grid <- expand.grid(
        policy = c("exclude", "assume_same_day", "indeterminate"),
        relation = c("on_or_after", "after", "before", "same_day", "within_days"),
        stringsAsFactors = FALSE
      )
      lapply(seq_len(nrow(grid)), function(row) {
        unname(unlist(grid[row, ], use.names = FALSE))
      })
    }
    for (case in cases) {
      policy <- case[[1L]]
      relation <- case[[2L]]
      window <- if (relation == "within_days") 2L else NULL
      expected <- nis_flag_pr_timing(query_data[[i]][[1L]], c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
        relation = relation, window = window, missing_day = policy)
      actual <- nis_flag_pr_timing(query_data[[i]][[2L]], c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
        relation = relation, window = window, missing_day = policy) |>
        dplyr::collect()
      expect_identical(actual, expected)
    }
  }
})
