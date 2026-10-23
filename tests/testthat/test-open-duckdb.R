test_that("nis_open reads native Parquet lazily and normalizes case drift", {
  path <- tempfile("nis-duckdb-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), Hosp_Nis = c(101L, 102L),
      AGE = c(40L, 70L)),
    file.path(path, "NIS_2019.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2020L, 2020L), Hosp_Nis = c(201L, 202L),
      AGE = c(65L, 30L)),
    file.path(path, "NIS_2020.parquet")
  )

  duckdb_query <- nis_open(path, years = 2020L)
  expect_s3_class(duckdb_query, "tbl_duckdb_connection")
  expect_true(all(c("YEAR", "HOSP_NIS") %in% colnames(duckdb_query)))
  expect_false("Hosp_Nis" %in% colnames(duckdb_query))

  duckdb_result <- duckdb_query |>
    dplyr::filter(AGE >= 50) |>
    dplyr::summarise(n = dplyr::n(), hospitals = dplyr::n_distinct(HOSP_NIS)) |>
    dplyr::collect()
  expect_equal(duckdb_result$n, 1)
  expect_error(nis_open(path, years = 2020L, engine = "duckdb"), "unused argument")
})

test_that("nis_open safely quotes paths containing spaces and apostrophes", {
  path <- file.path(tempdir(), "nis quoted 'path'")
  dir.create(path, showWarnings = FALSE)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  parquet <- file.path(path, "NIS_2019.parquet")
  write_duckdb_parquet(dplyr::tibble(YEAR = rep(2019L, 3)), parquet)
  query <- nis_open(path)
  result <- query |>
    dplyr::summarise(n = dplyr::n()) |>
    dplyr::collect()
  expect_equal(result$n, 3)
})

test_that("nis_open reads Hive year partitions and unions their schemas", {
  path <- tempfile("nis-hive-years-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), A = c(1L, 2L),
      drift = c(10L, 20L)),
    file.path(path, "YEAR=2019", "part.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = 2020L, B = 3L, drift = 30.5),
    file.path(path, "YEAR=2020", "part.parquet")
  )

  query <- nis_open(path)
  sql <- dbplyr::sql_render(query |> dplyr::select(YEAR, B))
  expect_match(sql, "read_parquet")
  expect_match(sql, "union_by_name = true")
  expect_match(sql, "hive_partitioning = false")
  plan <- DBI::dbGetQuery(query$src$con,
    paste("EXPLAIN (FORMAT JSON)", as.character(sql)))
  expect_match(plan[[2L]], '"Projections":\\s*\\[\\s*"YEAR",\\s*"B"\\s*\\]')
  all_years <- dplyr::collect(query |> dplyr::select(YEAR, A, B, drift))
  expect_equal(all_years$YEAR, c(2019L, 2019L, 2020L))
  expect_equal(all_years$A, c(1L, 2L, NA_integer_))
  expect_equal(all_years$B, c(NA_integer_, NA_integer_, 3L))
  expect_equal(all_years$drift, c(10, 20, 30.5))
  selected_year <- dplyr::collect(nis_open(path, years = 2020L) |>
    dplyr::select(YEAR, B, drift))
  expect_equal(selected_year$YEAR, 2020L)
  expect_equal(selected_year$drift, 30.5)
})

test_that("nis_open combines annual files with Hive partitions", {
  path <- tempfile("nis-mixed-layouts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L, annual_only = "a"),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 2L, hive_only = "b"),
    file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(nis_open(path) |> dplyr::select(YEAR, id,
    annual_only, hive_only))
  expect_identical(sort(result$YEAR), c(2019L, 2020L))
  expect_identical(sort(result$id), c(1L, 2L))
  expect_identical(result$annual_only[!is.na(result$annual_only)], "a")
  expect_identical(result$hive_only[!is.na(result$hive_only)], "b")
  selected <- dplyr::collect(nis_open(path, years = 2020L) |>
    dplyr::select(YEAR, id))
  expect_identical(selected$YEAR, 2020L)
  expect_identical(selected$id, 2L)
})

test_that("nis_open rejects a year represented in both layouts", {
  path <- tempfile("nis-duplicate-layouts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  annual <- file.path(path, "NIS_2020.parquet")
  hive <- file.path(path, "YEAR=2020")
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, id = 1L), annual)
  write_duckdb_parquet(dplyr::tibble(id = 2L), file.path(hive, "part.parquet"))

  expect_error(nis_open(path), "2020.*NIS_2020[.]parquet.*YEAR=2020.*Keep one layout")
})

test_that("nis_open checks mixed layouts only for selected years", {
  path <- tempfile("nis-selected-layout-conflict-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, id = 2L),
    file.path(path, "NIS_2020.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 3L),
    file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(nis_open(path, years = 2019L) |>
    dplyr::select(YEAR, id))
  expect_identical(result$YEAR, 2019L)
  expect_identical(result$id, 1L)
  expect_error(nis_open(path, years = 2020L),
    "Year 2020: annual .*NIS_2020[.]parquet.*Hive .*YEAR=2020")
})

test_that("nis_open accepts multiple Hive parts for one year", {
  path <- tempfile("nis-hive-multiple-parts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(id = 1:2),
    file.path(path, "YEAR=2020", "part-1.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 3L),
    file.path(path, "YEAR=2020", "part-2.parquet"))

  result <- dplyr::collect(nis_open(path) |> dplyr::select(YEAR, id))
  expect_identical(result$YEAR, rep(2020L, 3L))
  expect_identical(result$id, 1:3)
})

test_that("nis_open casts physical Hive years before combining annual files", {
  path <- tempfile("nis-mixed-year-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = "2020", id = 2L),
    file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(nis_open(path) |> dplyr::select(YEAR, id))
  expect_type(result$YEAR, "integer")
  expect_identical(result$YEAR, c(2019L, 2020L))
  expect_identical(result$id, c(1L, 2L))
})

test_that("nis_open casts YEAR to integer and rejects non-numeric years", {
  path <- tempfile("nis-year-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(
    YEAR = 2019L, I10_DX1 = "I509", I10_PR1 = "02703ZZ"
  ), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(
    YEAR = "2020", I10_DX1 = "J189", I10_PR1 = "0JH60DZ"
  ), file.path(path, "NIS_2020.parquet"))

  query <- nis_open(path)
  result <- query |>
    nis_flag_dx(hf = "I50") |>
    nis_flag_pr(proc = "02703") |>
    dplyr::collect()
  expect_type(result$YEAR, "integer")
  expect_identical(result$hf, c(TRUE, FALSE))
  expect_identical(result$proc, c(TRUE, FALSE))

  write_duckdb_parquet(dplyr::tibble(YEAR = "unknown"),
    file.path(path, "NIS_2021.parquet"))
  expect_error(nis_open(path, years = 2021L), "YEAR.*NIS_2021[.]parquet")

  for (bad_year in c("2019.5", "2147483648")) {
    write_duckdb_parquet(dplyr::tibble(YEAR = bad_year),
      file.path(path, "NIS_2022.parquet"))
    expect_error(nis_open(path, years = 2022L),
      "whole numbers within the integer range")
    unlink(file.path(path, "NIS_2022.parquet"))
  }
})

test_that("nis_open rejects physical years that conflict with Hive partitions", {
  path <- tempfile("nis-hive-year-conflict-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, NA_integer_), id = 1:2),
    file.path(path, "YEAR=2019", "part-a.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = 2020L, id = 3L),
    file.path(path, "YEAR=2019", "part-b.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(id = 4L),
    file.path(path, "YEAR=2020", "part.parquet")
  )

  expect_error(nis_open(path, years = 2019L),
    "physical.*YEAR=2019")
  valid_path <- tempfile("nis-hive-year-valid-")
  dir.create(valid_path)
  on.exit(unlink(valid_path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, NaN), id = 1:2),
    file.path(valid_path, "YEAR=2019", "part-a.parquet")
  )
  write_duckdb_parquet(dplyr::tibble(id = 3L),
    file.path(valid_path, "YEAR=2019", "part-b.parquet"))

  query <- nis_open(valid_path)
  expect_s3_class(query, "tbl_duckdb_connection")
  expect_equal(dplyr::collect(query |> dplyr::select(YEAR, id))$YEAR,
    c(2019L, 2019L, 2019L))
})

test_that("nis_open unions representative all-NA Parquet column types", {
  path <- tempfile("nis-nullable-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(
    YEAR = c(2019L, 2019L), nullable_integer = c(NA_integer_, NA_integer_),
    nullable_double = c(NA_real_, NA_real_),
    nullable_character = c(NA_character_, NA_character_),
    nullable_date = as.Date(c(NA_character_, NA_character_))
  ), file.path(path, "NIS_2019.parquet"))

  result <- dplyr::collect(nis_open(path))
  expect_type(result$nullable_integer, "integer")
  expect_type(result$nullable_double, "double")
  expect_type(result$nullable_character, "character")
  expect_s3_class(result$nullable_date, "Date")
  expect_true(all(is.na(result$nullable_integer)))
  expect_true(all(is.na(result$nullable_double)))
  expect_true(all(is.na(result$nullable_character)))
  expect_true(all(is.na(result$nullable_date)))
})

test_that("nis_open promotes numeric and character fields to character", {
  path <- tempfile("nis-incompatible-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, field = 1L),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, field = "two"),
    file.path(path, "NIS_2020.parquet"))

  query <- nis_open(path)
  expect_s3_class(query, "tbl_sql")
  result <- dplyr::collect(query |> dplyr::select(YEAR, field))
  expect_type(result$field, "character")
  expect_equal(result$field, c("1", "two"))
})

test_that("derived DuckDB queries retain the connection until all are released", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")

  path <- tempfile("nis-duckdb-finalizer-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data.frame(YEAR = 2019L),
    file.path(path, "NIS_2019.parquet"))

  query <- nis_open(path)
  con <- query$src$con
  lookup <- dplyr::tibble(YEAR = 2019L, adjustment = 2L)
  DBI::dbWriteTable(con, "lookup", lookup, temporary = TRUE)
  derived <- query |>
    dplyr::mutate(value = YEAR + 1L) |>
    dplyr::left_join(dplyr::tbl(con, "lookup"), by = "YEAR")
  expect_true(duckdb::dbIsValid(con))
  query <- NULL
  invisible(gc())
  expect_true(duckdb::dbIsValid(con))
  expect_equal(dplyr::collect(derived)$value, 2020L)
  derived <- NULL
  lookup <- NULL
  invisible(gc())
  expect_false(duckdb::dbIsValid(con))
})
