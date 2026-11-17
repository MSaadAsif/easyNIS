test_that("nonnumeric year types retain existing eligibility behavior", {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (year in list(NA, "2016")) {
    data <- data.frame(YEAR = year, I10_DX1 = "TOKEN", I10_PR1 = "TOKEN")
    for (flag in list(nis_flag_dx, nis_flag_pr)) {
      expect_identical(flag(data, hit = "TOKEN")$hit, TRUE)
      if (is.logical(year)) {
        query <- dplyr::copy_to(con, data, tempfile("year_"), temporary = TRUE)
        expect_identical(dplyr::collect(flag(query, hit = "TOKEN"))$hit, TRUE)
      }
    }
  }
})

test_that("code flags require finite whole years while preserving missing years", {
  data <- data.frame(
    id = 1:17,
    YEAR = c(2014.5, 2015.5, 2016.5, Inf, -Inf, -2014, 2011,
      NaN, NA, 2014, rep(2015, 6), 2016),
    DQTR = c(rep(NA_real_, 10), 1, 2, 3, 4, NA, 5, NA),
    DX1 = "TOKEN1", PR1 = "TOKEN1", I10_DX1 = "TOKEN1", I10_PR1 = "TOKEN1"
  )
  expected <- list(
    icd9 = c(rep(FALSE, 7), TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
      FALSE, TRUE, FALSE, FALSE),
    icd10 = c(rep(FALSE, 7), TRUE, TRUE, FALSE, FALSE, FALSE, FALSE,
      TRUE, TRUE, FALSE, TRUE)
  )
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  query <- dplyr::copy_to(con, data, "year_validity", temporary = TRUE)
  # Exercise a SQL NaN as well as the NULL produced when copying R missing values.
  DBI::dbExecute(con, "UPDATE year_validity SET YEAR = 'NaN'::DOUBLE WHERE id = 8")

  for (system in names(expected)) {
    for (flag in list(nis_flag_dx, nis_flag_pr)) {
      local <- flag(data, hit = "TOKEN", system = system)
      remote <- dplyr::collect(dplyr::arrange(
        flag(query, hit = "TOKEN", system = system), id
      ))
      expect_identical(local$hit, expected[[system]])
      expect_identical(remote$hit, expected[[system]])
    }
  }
})

test_that("absent YEAR leaves code-system version eligibility unchanged", {
  data <- data.frame(
    id = 1:5, DQTR = c(1, 4, 5, NA, 3),
    DXVER = c(9, 10, NA, 8, NaN), PRVER = c(9, 10, NA, 8, NaN),
    DX1 = "TOKEN1", PR1 = "TOKEN1", I10_DX1 = "TOKEN1", I10_PR1 = "TOKEN1"
  )
  expected <- list(icd9 = c(TRUE, FALSE, TRUE, FALSE, TRUE),
    icd10 = c(FALSE, TRUE, TRUE, FALSE, TRUE))
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  query <- dplyr::copy_to(con, data, "absent_year", temporary = TRUE)

  for (system in names(expected)) {
    for (flag in list(nis_flag_dx, nis_flag_pr)) {
      local <- flag(data, hit = "TOKEN", system = system)
      remote <- dplyr::collect(dplyr::arrange(
        flag(query, hit = "TOKEN", system = system), id
      ))
      expect_identical(local$hit, expected[[system]])
      expect_identical(remote$hit, expected[[system]])
      no_indicators <- dplyr::select(data, -DXVER, -PRVER, -DQTR)
      expect_true(all(flag(no_indicators, hit = "TOKEN", system = system)$hit))
      remote_no_indicators <- dplyr::select(query, -DXVER, -PRVER, -DQTR)
      expect_true(all(dplyr::collect(
        flag(remote_no_indicators, hit = "TOKEN", system = system)
      )$hit))
    }
  }
})
