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
  expect_error(nis_open(path, years = 2020L, engine = "arrow"), "unused argument")
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
  expect_match(sql, "hive_partitioning = true")
  plan <- DBI::dbGetQuery(query$src$con, paste("EXPLAIN", as.character(sql)))
  plan_text <- gsub("[^[:alnum:]]", "", plan[[2L]])
  expect_match(plan_text, "ProjectionsYEARB")
  expect_false(grepl("Projections:.*A", plan_text))
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

test_that("nis_open reports incompatible annual Parquet types clearly", {
  path <- tempfile("nis-incompatible-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, field = 1L),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, field = "two"),
    file.path(path, "NIS_2020.parquet"))

  query <- nis_open(path)
  expect_s3_class(query, "tbl_sql")
  expect_equal(dplyr::collect(query |> dplyr::select(YEAR, field))$field,
    c("1", "two"))
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
