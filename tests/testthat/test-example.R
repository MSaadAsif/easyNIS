test_that("nis_example writes the documented annual layouts and coding eras", {
  configs <- list(2012L, c(2015L, 2016L), c(2022L, 2023L))
  expected_years <- unlist(configs, use.names = FALSE)
  paths <- lapply(configs, nis_example)
  on.exit(unlink(unlist(paths), recursive = TRUE), add = TRUE)

  records <- do.call(c, Map(function(path, years) {
    lapply(years, function(year) {
      open_duckdb_dataset(file.path(path, paste0("NIS_", year, ".parquet"))) |>
        dplyr::collect()
    })
  }, paths, configs))

  expect_identical(vapply(records, function(data) unique(data$YEAR), integer(1)), expected_years)
  expect_true(all(vapply(records, function(data) all(data$DISCWT > 0), logical(1))))
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

test_that("failed fixture writes close their connection and remove their destination", {
  write_part <- nis_duckdb_write_parquet
  paths <- character()
  connections <- list()
  local_mocked_bindings(nis_duckdb_write_parquet = function(data, path, con) {
    paths <<- c(paths, path)
    connections[[length(connections) + 1L]] <<- con
    if (length(paths) == 2L) stop("fixture write interrupted")
    write_part(data, path, con)
  })

  expect_error(nis_example(2019:2020), "fixture write interrupted")
  expect_length(paths, 2L)
  expect_identical(connections[[1L]], connections[[2L]])
  expect_false(DBI::dbIsValid(connections[[1L]]))
  expect_false(dir.exists(dirname(dirname(paths[[1L]]))))
})
