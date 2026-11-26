for (release_reader in c("duckdb", "arrow")) {
  test_that(paste("only unmarked parts contribute to release totals with", release_reader), {
    if (release_reader == "arrow") {
      skip_if_not_installed("arrow")
    }

    path <- nis_example(2019:2020)
    withr::defer(unlink(path, recursive = TRUE))
    expect_no_warning(query <- nis_open(path, reader = release_reader))
    data <- dplyr::collect(query)
    annual <- data[data$YEAR == 2020L, ]

    unmarked <- withr::local_tempdir()
    annual_file <- file.path(unmarked, "NIS_2020.parquet")
    if (release_reader == "arrow") {
      arrow::write_parquet(annual, annual_file)
    } else {
      write_duckdb_parquet(annual, annual_file)
    }
    expect_warning(
      nis_open(unmarked, reader = release_reader),
      "2020: unweighted discharges",
      class = "easynis_release_mismatch"
    )

    mixed_year <- file.path(path, "NIS_2020.parquet")
    expect_true(file.copy(annual_file, file.path(mixed_year, "part-1.parquet")))
    pattern <- "(?s)^(?!.*2019:).*2020: unweighted discharges 96 [(]expected"
    expect_warning(nis_open(path, reader = release_reader), pattern, class = "easynis_release_mismatch", perl = TRUE)

    unlink(file.path(mixed_year, "part-0.parquet"))
    expect_warning(nis_open(path, reader = release_reader), pattern, class = "easynis_release_mismatch", perl = TRUE)
  })
}

test_that("complete releases open quietly within HCUP's weight precision", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2019:2020,
      rows = c(3, 3),
      weight = c(15, 15),
      hospitals = c(2, 2)
    )
  )
  path <- withr::local_tempdir()
  data <- data.frame(YEAR = 2019L, DISCWT = c(5, 5, 5.5), HOSP_NIS = c(1L, 1L, 2L), NIS_STRATUM = 1011L)
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(data[names(data) != "YEAR"], file.path(path, "YEAR=2020", "part.parquet"))

  expect_no_warning(query <- nis_open(path))
  expect_s3_class(query, "tbl_sql")
  counts <- dplyr::collect(dplyr::count(query, YEAR, sort = FALSE))
  expect_equal(as.numeric(counts$n[order(counts$YEAR)]), c(3, 3))
})

test_that("the default check flags a missing quarter", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2020L,
      rows = 12,
      weight = 60,
      hospitals = 4
    )
  )
  path <- withr::local_tempdir()
  annual <- file.path(path, "NIS_2020.parquet")
  data <- data.frame(YEAR = 2020L, DQTR = rep(1:4, each = 3), discwt = 5, hosp_nis = rep(1:4, each = 3))
  write_duckdb_parquet(data[data$DQTR != 4L, ], annual)

  expect_warning(
    query <- nis_open(path),
    class = "easynis_release_mismatch",
    regexp = paste0(
      "(?s)2020.*discharges.*9.*12.*DISCWT.*45.*60.*HOSP_NIS.*3.*4",
      ".*Cohort extracts.*check_release = FALSE"
    ),
    perl = TRUE
  )
  expect_equal(nrow(dplyr::collect(query)), 9L)
})

test_that("the default check flags a release missing three of four Parquet parts", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2020L,
      rows = 12,
      weight = 60,
      hospitals = 4
    )
  )
  path <- withr::local_tempdir()
  full_path <- file.path(path, "full")
  partial_path <- file.path(path, "partial")
  for (quarter in 1:4) {
    part <- file.path("YEAR=2020", paste0("part-", quarter, ".parquet"))
    data <- data.frame(DQTR = rep(quarter, 3), DISCWT = 5, HOSP_NIS = quarter)
    write_duckdb_parquet(data, file.path(full_path, part))
    if (quarter == 1L) write_duckdb_parquet(data, file.path(partial_path, part))
  }

  expect_no_warning(nis_open(full_path))
  expect_warning(
    nis_open(partial_path),
    "2020: unweighted discharges 3 [(]expected 12[)]",
    class = "easynis_release_mismatch"
  )
  expect_no_warning(nis_open(partial_path, check_release = FALSE))
})

test_that("release checks report corrupt design fields in marked files", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2019L,
      rows = 12,
      weight = 60,
      hospitals = 4
    )
  )
  path <- withr::local_tempdir()
  con <- nis_duckdb_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  nis_duckdb_write_parquet(
    data.frame(
      YEAR = c(2019L, 2020L, NA_integer_),
      DISCWT = 5,
      HOSP_NIS = c(1L, 1L, 2L),
      NIS_STRATUM = c(0L, 1011L, -1L)
    ),
    file.path(path, "NIS_2019.parquet"),
    con
  )

  expect_warning(
    query <- nis_open(path),
    class = "easynis_release_mismatch",
    regexp = "(?s)YEAR.*2020.*2019.*NIS_STRATUM <= 0: 2",
    perl = TRUE
  )
  expect_equal(sort(dplyr::collect(query)$YEAR, na.last = TRUE), c(2019L, 2020L, NA_integer_))
})

test_that("unreferenced years still get integrity checks", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2019L,
      rows = 1,
      weight = 5,
      hospitals = 1
    )
  )
  path <- withr::local_tempdir()
  data <- data.frame(YEAR = 2019L, DISCWT = 5, HOSP_NIS = 1L)
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))
  data$YEAR <- 2020L
  data$DISCWT <- NA_real_
  write_duckdb_parquet(data, file.path(path, "NIS_2020.parquet"))

  expect_no_warning(nis_open(path))
  expect_no_warning(nis_open(path, years = 2020L))

  bad_path <- withr::local_tempdir()
  write_duckdb_parquet(data.frame(NIS_STRATUM = 0L), file.path(bad_path, "NIS_2020.parquet"))
  expect_warning(nis_open(bad_path), class = "easynis_release_mismatch", regexp = "NIS_STRATUM <= 0: 1")
})

test_that("only finite positive hospital IDs count toward release totals", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2020L,
      rows = 8,
      weight = 40,
      hospitals = 7
    )
  )
  path <- withr::local_tempdir()
  con <- nis_duckdb_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  file <- DBI::dbQuoteString(con, file.path(path, "NIS_2020.parquet"))
  # SQL keeps NaN distinct from NULL in the Parquet fixture.
  DBI::dbExecute(
    con,
    paste(
      "COPY (SELECT 2020::INTEGER AS YEAR, 5 AS DISCWT, id::DOUBLE AS HOSP_NIS",
      "FROM (VALUES ('1'), ('2'), ('NaN'), ('Infinity'), ('-9'), ('-8'), ('0'), (NULL)) ids(id))",
      "TO",
      file,
      "(FORMAT PARQUET)"
    )
  )

  expect_warning(nis_open(path), "HOSP_NIS 2", class = "easynis_release_mismatch")
})

test_that("release totals skip design fields absent from an annual schema", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2019:2020,
      rows = c(1, 2),
      weight = c(5, 10),
      hospitals = c(1, 2)
    )
  )
  path <- withr::local_tempdir()
  write_duckdb_parquet(data.frame(YEAR = 2019L), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(data.frame(DISCWT = 5, HOSP_NIS = 1L), file.path(path, "YEAR=2020", "core.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020L), file.path(path, "YEAR=2020", "projected.parquet"))

  expect_no_warning(nis_open(path, years = 2019L))
  expect_no_warning(nis_open(path))
  write_duckdb_parquet(
    data.frame(YEAR = 2019L, DISCWT = NA_real_, HOSP_NIS = NA_integer_),
    file.path(path, "NIS_2019.parquet")
  )
  expect_warning(nis_open(path), class = "easynis_release_mismatch")
})

test_that("a marked schema-only annual file warns even without a physical YEAR column", {
  path <- withr::local_tempdir()
  con <- nis_duckdb_connect()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  nis_duckdb_write_parquet(data.frame(DISCWT = numeric()), file.path(path, "NIS_2020.parquet"), con)
  expect_warning(query <- nis_open(path), "2020.*0", class = "easynis_release_mismatch")
  expect_equal(nrow(dplyr::collect(query)), 0L)
})

test_that("release discrepancies are reported in year order", {
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2019:2020,
      rows = 2,
      weight = 10,
      hospitals = 2
    )
  )
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  path <- withr::local_tempdir()
  write_duckdb_parquet(data.frame(YEAR = 2020L, HOSP_NIS = 1L), file.path(path, "NIS_2020.parquet"))
  write_duckdb_parquet(data.frame(HOSP_NIS = 1L), file.path(path, "YEAR=2019", "part.parquet"))

  expect_warning(nis_open(path, years = 2020:2019), "(?s)2019:.*2020:", class = "easynis_release_mismatch", perl = TRUE)
})
