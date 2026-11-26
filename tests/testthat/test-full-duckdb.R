skip_unless_full_tests <- function() {
  skip_if_not(
    tolower(Sys.getenv("EASYNIS_FULL_TESTS")) %in% c("true", "1"),
    "Set EASYNIS_FULL_TESTS=true to run the DuckDB resource-intensive tests."
  )
}

test_that("procedure timing agrees with DuckDB on a full-width Parquet layout", {
  skip_unless_full_tests()
  data <- pr_timing_parity_data()
  for (slot in 5:25) {
    data[[paste0("I10_PR", slot)]] <- "OTHER"
  }
  data$I10_PR12 <- "OUT"
  for (slot in 5:11) {
    data[[paste0("PRDAY", slot)]] <- 1L
  }
  data <- dplyr::select(data, dplyr::starts_with("I10_PR"), dplyr::starts_with("PRDAY"), YEAR, PRVER)
  path <- withr::local_tempdir()
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)

  cases <- list(c("exclude", "on_or_after"), c("indeterminate", "on_or_after"), c("indeterminate", "within_days"))
  for (case in cases) {
    policy <- case[[1L]]
    relation <- case[[2L]]
    window <- if (relation == "within_days") 2L else NULL
    expected <- nis_flag_pr_timing(
      data,
      c("IX", "IDX", "NOMATCH"),
      c("OUT", "ALT"),
      relation = relation,
      window = window,
      missing_day = policy
    )
    actual <- nis_flag_pr_timing(
      query,
      c("IX", "IDX", "NOMATCH"),
      c("OUT", "ALT"),
      relation = relation,
      window = window,
      missing_day = policy
    ) |>
      dplyr::collect()
    expect_identical(actual, expected, info = paste(policy, relation))
  }
})
