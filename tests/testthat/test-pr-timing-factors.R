test_that("factor procedure-day labels obey documented missing-day modes", {
  data <- data.frame(
    I10_PR1 = rep("IX", 8L),
    I10_PR2 = rep("OUT", 8L),
    PRDAY1 = factor(c("1", "1", "0", "0", "-99", NA, "2", "0")),
    PRDAY2 = factor(c("0", "2", "-99", NA, "1", "1", "0", "0")),
    group = ordered(rep(c("B", "A"), 4L), levels = c("B", "A"))
  )
  expected <- list(
    exclude = c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
    assume_same_day = c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
    indeterminate = c(FALSE, TRUE, NA, NA, NA, NA, FALSE, TRUE)
  )
  for (policy in names(expected)) {
    actual <- nis_flag_pr_timing(data, "IX", "OUT", missing_day = policy)
    expect_identical(actual$outcome_post_index, expected[[policy]], info = policy)
    expect_identical(actual[names(data)], data)
  }
})

test_that("factor day labels match numeric days across level orders and relations", {
  reference <- dplyr::tibble(
    I10_PR1 = rep("IX", 8L),
    I10_PR2 = rep("OUT", 8L),
    PRDAY1 = c(1, 1, 0, 0, -99, NA, 2, 0),
    PRDAY2 = c(0, 2, -99, NA, 1, 1, 0, 0),
    group = factor(rep(c("B", "A"), 4L), levels = c("B", "A"))
  )
  variants <- expand.grid(ordered = c(FALSE, TRUE), reverse = c(FALSE, TRUE))
  for (variant in seq_len(nrow(variants))) {
    ordered <- variants$ordered[[variant]]
    reverse <- variants$reverse[[variant]]
    levels <- c("-99", "0", "1", "2")
    if (reverse) {
      levels <- rev(levels)
    }
    data <- reference
    data$PRDAY1 <- factor(data$PRDAY1, levels = levels, ordered = ordered)
    data$PRDAY2 <- factor(data$PRDAY2, levels = levels, ordered = ordered)
    for (policy in c("exclude", "assume_same_day", "indeterminate")) {
      for (relation in c("on_or_after", "after", "before", "same_day", "within_days")) {
        window <- if (relation == "within_days") 1L else NULL
        expected <- nis_flag_pr_timing(
          reference,
          "IX",
          "OUT",
          relation = relation,
          window = window,
          missing_day = policy
        )$outcome_post_index
        actual <- nis_flag_pr_timing(data, "IX", "OUT", relation = relation, window = window, missing_day = policy)
        expect_identical(actual$outcome_post_index, expected, info = paste(ordered, reverse, policy, relation))
        expect_identical(actual[names(data)], data)
      }
    }
  }
})

test_that("DuckDB and local factor procedure days agree", {
  for (ordered in c(FALSE, TRUE)) {
    data <- dplyr::tibble(
      I10_PR1 = rep("IX", 8L),
      I10_PR2 = rep("OUT", 8L),
      PRDAY1 = factor(c("1", "1", "0", "0", "-99", NA, "2", "0"), levels = c("2", "1", "0", "-99"), ordered = ordered),
      PRDAY2 = factor(c("0", "2", "-99", NA, "1", "1", "0", "0"), levels = c("-99", "0", "1", "2"), ordered = ordered)
    )
    query <- duckdb_query_fixture(data)
    for (policy in c("exclude", "assume_same_day", "indeterminate")) {
      for (relation in c("on_or_after", "after", "before", "same_day", "within_days")) {
        window <- if (relation == "within_days") 1L else NULL
        expected <- nis_flag_pr_timing(
          data,
          "IX",
          "OUT",
          relation = relation,
          window = window,
          missing_day = policy
        )$outcome_post_index
        actual <- nis_flag_pr_timing(query, "IX", "OUT", relation = relation, window = window, missing_day = policy)
        expect_s3_class(actual, "tbl_sql")
        expect_identical(dplyr::collect(actual)$outcome_post_index, expected, info = paste(ordered, policy, relation))
      }
    }
  }
})

test_that("decoded factor missing and invalid days obey each policy", {
  cases <- list(
    explicit_na_level = factor(NA_character_, exclude = NULL),
    nan_label = factor(NaN),
    negative_sentinel = factor("-99")
  )
  expected <- list(
    exclude = c(FALSE, FALSE, FALSE),
    assume_same_day = c(TRUE, TRUE, TRUE),
    indeterminate = c(NA, NA, NA)
  )

  for (case in seq_along(cases)) {
    data <- dplyr::tibble(I10_PR1 = "IX", I10_PR2 = "OUT", PRDAY1 = 0L, PRDAY2 = cases[[case]])
    query <- duckdb_query_fixture(data)
    for (policy in names(expected)) {
      local <- nis_flag_pr_timing(data, "IX", "OUT", missing_day = policy)
      expect_identical(local$outcome_post_index, expected[[policy]][[case]], info = paste(names(cases)[[case]], policy))
      actual <- dplyr::collect(nis_flag_pr_timing(query, "IX", "OUT", missing_day = policy))
      expect_identical(actual$outcome_post_index, local$outcome_post_index, info = paste(names(cases)[[case]], policy))
    }
  }
})

test_that("non-finite procedure days follow the missing-day policy", {
  data <- data.frame(
    id = 1:5,
    I10_PR1 = "IX",
    I10_PR2 = "OUT",
    PRDAY1 = c(0, Inf, -Inf, 1, 0),
    PRDAY2 = c(Inf, 1, 1, 2, -Inf)
  )
  path <- withr::local_tempdir()
  write_duckdb_parquet(data, file.path(path, "NIS_2020.parquet"))
  query <- nis_open(path, check_release = FALSE)
  expected <- list(
    exclude = c(FALSE, FALSE, FALSE, TRUE, FALSE),
    assume_same_day = c(FALSE, TRUE, TRUE, TRUE, FALSE),
    indeterminate = c(NA, NA, NA, TRUE, NA)
  )

  for (input in list(data, query)) {
    for (policy in names(expected)) {
      result <- nis_flag_pr_timing(input, "IX", "OUT", relation = "after", missing_day = policy)
      if (inherits(result, "tbl_sql")) {
        result <- dplyr::collect(dplyr::arrange(result, id))
      }
      expect_identical(result$outcome_post_index, expected[[policy]], info = policy)
    }
  }
})
