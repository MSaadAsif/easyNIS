test_that("integer, character, and factor years agree across code systems and backends", {
  years <- c(2011L, 2012L, 2014L, 2015L, 2015L, 2015L, 2015L, 2016L, NA_integer_)
  labels <- c(as.character(years), "02015", "2016.5", "abc", "2e3", "2016\n", "", "2147483648")
  expected_old <- c(FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, rep(FALSE, 6L))
  expected_new <- c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE, rep(FALSE, 7L))
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  add_flags <- function(data) {
    data |>
      nis_flag_dx(dx_old = "TOKEN", system = "icd9") |>
      nis_flag_dx(dx_new = "TOKEN", system = "icd10") |>
      nis_flag_pr(pr_old = "TOKEN", system = "icd9") |>
      nis_flag_pr(pr_new = "TOKEN", system = "icd10")
  }

  for (year in list(years, labels, factor(labels, levels = rev(sort(unique(labels)))))) {
    rows <- seq_along(year)
    data <- data.frame(
      id = rows,
      YEAR = year,
      DQTR = c(4L, 4L, 4L, 3L, 4L, NA_integer_, 5L, 1L, 5L, 3L, rep(NA_integer_, 6L))[rows],
      DX1 = "TOKEN1",
      PR1 = "TOKEN1",
      I10_DX1 = "TOKEN1",
      I10_PR1 = "TOKEN1"
    )
    expected <- data.frame(dx_old = expected_old[rows], dx_new = expected_new[rows])
    expected$pr_old <- expected$dx_old
    expected$pr_new <- expected$dx_new

    expect_no_warning(local <- add_flags(data))
    expect_identical(local[names(expected)], expected)
    expect_identical(local$YEAR, year)

    DBI::dbWriteTable(con, "discharges", data, overwrite = TRUE)
    query <- dplyr::tbl(con, "discharges")
    DBI::dbExecute(con, "ALTER TABLE discharges RENAME TO offline_discharges")
    lazy <- add_flags(query)
    expect_s3_class(lazy, "tbl_sql")
    DBI::dbExecute(con, "ALTER TABLE offline_discharges RENAME TO discharges")

    observed <- lazy |> dplyr::arrange(id) |> dplyr::collect()
    expect_identical(as.data.frame(observed[names(expected)]), expected)
    expect_identical(observed$YEAR, year)
    expect_identical(names(observed), names(local))
  }
})

test_that("missing logical years leave code-system eligibility open", {
  data <- data.frame(YEAR = NA, I10_DX1 = "TOKEN", I10_PR1 = "TOKEN")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  query <- dplyr::copy_to(con, data, "missing_year", temporary = TRUE)
  for (flag in list(nis_flag_dx, nis_flag_pr)) {
    expect_identical(flag(data, hit = "TOKEN")$hit, TRUE)
    expect_identical(dplyr::collect(flag(query, hit = "TOKEN"))$hit, TRUE)
  }
})

test_that("code flags require finite whole years while preserving missing years", {
  data <- data.frame(
    id = 1:17,
    YEAR = c(2014.5, 2015.5, 2016.5, Inf, -Inf, -2014, 2011, NaN, NA, 2014, rep(2015, 6), 2016),
    DQTR = c(rep(NA_real_, 10), 1, 2, 3, 4, NA, 5, NA),
    DX1 = "TOKEN1",
    PR1 = "TOKEN1",
    I10_DX1 = "TOKEN1",
    I10_PR1 = "TOKEN1"
  )
  expected <- list(
    icd9 = c(rep(FALSE, 7), TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE),
    icd10 = c(rep(FALSE, 7), TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE)
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
        flag(query, hit = "TOKEN", system = system),
        id
      ))
      expect_identical(local$hit, expected[[system]])
      expect_identical(remote$hit, expected[[system]])
    }
  }
})

test_that("absent YEAR leaves code-system version eligibility unchanged", {
  data <- data.frame(
    id = 1:5,
    DQTR = c(1, 4, 5, NA, 3),
    DXVER = c(9, 10, NA, 8, NaN),
    PRVER = c(9, 10, NA, 8, NaN),
    DX1 = "TOKEN1",
    PR1 = "TOKEN1",
    I10_DX1 = "TOKEN1",
    I10_PR1 = "TOKEN1"
  )
  expected <- list(icd9 = c(TRUE, FALSE, TRUE, FALSE, TRUE), icd10 = c(FALSE, TRUE, TRUE, FALSE, TRUE))
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  query <- dplyr::copy_to(con, data, "absent_year", temporary = TRUE)

  for (system in names(expected)) {
    for (flag in list(nis_flag_dx, nis_flag_pr)) {
      local <- flag(data, hit = "TOKEN", system = system)
      remote <- dplyr::collect(dplyr::arrange(
        flag(query, hit = "TOKEN", system = system),
        id
      ))
      expect_identical(local$hit, expected[[system]])
      expect_identical(remote$hit, expected[[system]])
      no_indicators <- dplyr::select(data, -DXVER, -PRVER, -DQTR)
      expect_true(all(flag(no_indicators, hit = "TOKEN", system = system)$hit))
      remote_no_indicators <- dplyr::select(query, -DXVER, -PRVER, -DQTR)
      expect_true(all(
        dplyr::collect(
          flag(remote_no_indicators, hit = "TOKEN", system = system)
        )$hit
      ))
    }
  }
})

test_that("DuckDB checks fractional decimal years without rounding to double", {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  data <- dplyr::tbl(
    con,
    dbplyr::sql(paste(
      "SELECT id, CAST(y AS DECIMAL(38, 30)) AS \"YEAR\", 'TOKEN' AS I10_DX1",
      "FROM (VALUES (1, '2016.0'), (2, '2016.0000000000000000001'), (3, NULL)) AS years(id, y)"
    ))
  )
  result <- data |>
    nis_flag_dx(hit = "TOKEN") |>
    dplyr::arrange(id) |>
    dplyr::collect()
  expect_identical(result$hit, c(TRUE, FALSE, TRUE))
})
