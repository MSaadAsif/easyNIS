skip_unless_full_tests <- function() {
  skip_if_not(identical(Sys.getenv("EASYNIS_FULL_TESTS"), "true"),
    "Set EASYNIS_FULL_TESTS=true to run the DuckDB resource-intensive tests.")
}

test_that("an export that exceeds the configured spill cap fails and releases spill space", {
  skip_unless_full_tests()

  spill <- withr::local_tempdir()
  path <- nis_example(2020L)
  withr::defer(unlink(path, recursive = TRUE))
  withr::local_options(easyNIS.duckdb_config = list(
    memory_limit = "32MB", max_temp_directory_size = "1MB", threads = 1L,
    preserve_insertion_order = FALSE, temp_directory = spill
  ))
  query <- nis_open(path)
  con <- dbplyr::remote_con(query)
  file <- file.path(spill, "sorted.parquet")
  output <- DBI::dbQuoteString(con, file)
  sql <- paste0("COPY (SELECT i, md5(i::VARCHAR) AS tag FROM range(1000000) AS t(i) ",
    "ORDER BY tag, i) TO ", output, " (FORMAT PARQUET)")
  expect_error(DBI::dbExecute(con, sql), "max_temp_directory_size")
  unlink(file)
  rm(query)
  invisible(gc())
  expect_false(DBI::dbIsValid(con))
  expect_true(dir.exists(spill))
  expect_length(list.files(spill, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("procedure timing agrees with DuckDB on a full-width Parquet layout", {
  skip_unless_full_tests()
  data <- pr_timing_parity_data()
  for (slot in 5:25) data[[paste0("I10_PR", slot)]] <- "OTHER"
  data$I10_PR12 <- "OUT"
  for (slot in 5:11) data[[paste0("PRDAY", slot)]] <- 1L
  data <- dplyr::select(data, dplyr::starts_with("I10_PR"),
    dplyr::starts_with("PRDAY"), YEAR, PRVER)
  path <- withr::local_tempdir()
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)

  cases <- list(c("exclude", "on_or_after"), c("indeterminate", "on_or_after"),
    c("indeterminate", "within_days"))
  for (case in cases) {
    policy <- case[[1L]]
    relation <- case[[2L]]
    window <- if (relation == "within_days") 2L else NULL
    expected <- nis_flag_pr_timing(data, c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
      relation = relation, window = window, missing_day = policy)
    actual <- nis_flag_pr_timing(query, c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
      relation = relation, window = window, missing_day = policy) |>
      dplyr::collect()
    expect_identical(actual, expected, info = paste(policy, relation))
  }
})
