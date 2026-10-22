test_that("nis_cost validates each input boundary", {
  valid <- data.frame(YEAR = 2020, TOTCHG = 1000, CCR_NIS = 0.25)

  expect_error(nis_cost(list(), 2020), "collected data frame")
  expect_error(nis_cost(valid, 2020, charges = character()), "single column name")
  expect_error(nis_cost(valid, 2020, charges = c("TOTCHG", "OTHER")),
    "single column name")
  expect_error(nis_cost(valid, 2020, charges = NA_character_),
    "single column name")
  expect_error(nis_cost(valid, NA_real_), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, 2020.5), "one year from 2012 through 2024")
  expect_error(nis_cost(valid, c(2020, 2021)), "one year from 2012 through 2024")

  valid$YEAR <- "2020"
  expect_error(nis_cost(valid, 2020), "must be numeric")
})

test_that("nis_cost_provenance validates its supported inputs", {
  expect_null(nis_cost_provenance(data.frame()))
  expect_error(nis_cost_provenance(list()), "data frame or survey design")
})

test_that("nis_example keeps annual layouts and invented values stable", {
  expected_years <- c(2012L, 2015L, 2016L, 2022L, 2023L)
  paths <- lapply(expected_years, nis_example)
  on.exit(unlink(unlist(paths), recursive = TRUE), add = TRUE)

  records <- Map(function(path, year) {
    open_duckdb_dataset(file.path(path, paste0("NIS_", year, ".parquet"))) |>
      dplyr::collect()
  }, paths, expected_years)

  expect_identical(vapply(records, nrow, integer(1)), rep(96L, 5L))
  expect_false(any(grepl("^I10_", names(records[[1L]]))))
  expect_true(all(c("DXVER", "PRVER", "DX1", "PR1", "NDX", "NPR") %in%
    names(records[[2L]])))
  expect_true(all(c("I10_DX1", "I10_PR1", "DXVER", "PRVER") %in%
    names(records[[2L]])))
  expect_false("I10_DX31" %in% names(records[[2L]]))
  expect_true(all(c("I10_DX40", "I10_PR25") %in% names(records[[3L]])))
  expect_true(all(c("APRDRG_RISK_MORTALITY", "APRDRG_SEVERITY", "DRG_NOPOA",
    "MDC_NOPOA") %in% names(records[[4L]])))
  expect_true(all(c("APRDRG_Risk_Mortality", "APRDRG_Severity", "DRG_NoPOA",
    "MDC_NoPOA") %in% names(records[[5L]])))
  expect_identical(records[[1L]]$YEAR, rep(2012L, 96L))
  expect_identical(records[[4L]]$I10_DX1[1:4], c("I5022", "I5022", "J189", "I5022"))

  duplicate_path <- nis_example(c(2023, 2012, 2023))
  on.exit(unlink(duplicate_path, recursive = TRUE), add = TRUE)
  expect_setequal(list.files(duplicate_path), c("NIS_2023.parquet", "NIS_2012.parquet"))
  duplicate_records <- open_duckdb_dataset(file.path(
    duplicate_path, "NIS_2023.parquet"
  )) |> dplyr::collect()
  expect_identical(duplicate_records, records[[5L]])
})
