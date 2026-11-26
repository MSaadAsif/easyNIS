test_that("complete releases open quietly within HCUP's weight precision", {
  local_mocked_bindings(nis_release_reference = data.frame(
    year = 2019:2020, rows = c(3, 3), weight = c(15, 15), hospitals = c(2, 2)
  ))
  path <- withr::local_tempdir()
  data <- data.frame(YEAR = 2019L, DISCWT = c(5, 5, 5.5),
    HOSP_NIS = c(1L, 1L, 2L), NIS_STRATUM = 1011L)
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(data[names(data) != "YEAR"],
    file.path(path, "YEAR=2020", "part.parquet"))

  expect_no_warning(query <- nis_open(path, check_release = TRUE))
  expect_s3_class(query, "tbl_sql")
  counts <- dplyr::collect(dplyr::count(query, YEAR, sort = FALSE))
  expect_equal(as.numeric(counts$n[order(counts$YEAR)]), c(3, 3))
})

test_that("release checks distinguish a dropped row from an intentional extract", {
  local_mocked_bindings(nis_release_reference = data.frame(
    year = 2020L, rows = 3, weight = 15, hospitals = 2
  ))
  path <- withr::local_tempdir()
  write_duckdb_parquet(
    data.frame(YEAR = 2020L, discwt = c(5, 5), hosp_nis = 1L),
    file.path(path, "NIS_2020.parquet")
  )

  expect_warning(
    query <- nis_open(path, check_release = TRUE),
    class = "easynis_release_mismatch",
    regexp = paste0("2020.*discharges.*2.*3.*DISCWT.*10.*15.*HOSP_NIS.*1.*2")
  )
  expect_equal(nrow(dplyr::collect(query)), 2L)
  expect_no_warning(nis_open(path))
})

test_that("release checks report corrupt design fields and keep the data open", {
  local_mocked_bindings(nis_release_reference = data.frame(
    year = 2019L, rows = 3, weight = 15, hospitals = 2
  ))
  path <- withr::local_tempdir()
  write_duckdb_parquet(
    data.frame(YEAR = c(2019L, 2019L, 172L), DISCWT = 5,
      HOSP_NIS = c(1L, 1L, 2L), NIS_STRATUM = c(1011L, 1011L, 0L)),
    file.path(path, "NIS_2019.parquet")
  )

  warning_text <- character()
  query <- withCallingHandlers(nis_open(path, check_release = TRUE),
    easynis_release_mismatch = function(condition) {
      warning_text <<- c(warning_text, conditionMessage(condition))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warning_text, 1L)
  expect_match(warning_text, "YEAR.*172.*2019")
  expect_match(warning_text, "NIS_STRATUM")
  expect_equal(sort(dplyr::collect(query)$YEAR), c(172L, 2019L, 2019L))
})

test_that("years without a reference are skipped even in a pooled release", {
  local_mocked_bindings(nis_release_reference = data.frame(
    year = 2019L, rows = 1, weight = 5, hospitals = 1
  ))
  path <- withr::local_tempdir()
  data <- data.frame(YEAR = 2019L, DISCWT = 5, HOSP_NIS = 1L)
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))
  data$YEAR <- 2020L
  data$DISCWT <- NA_real_
  write_duckdb_parquet(data, file.path(path, "NIS_2020.parquet"))

  expect_no_warning(nis_open(path, check_release = TRUE))
  expect_no_warning(nis_open(path, years = 2020L, check_release = TRUE))
})
