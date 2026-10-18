test_that("nis_open can hand its normalized Arrow query to DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")

  path <- tempfile("nis-duckdb-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  arrow::write_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), Hosp_Nis = c(101L, 102L),
      AGE = c(40L, 70L)),
    file.path(path, "NIS_2019.parquet")
  )
  arrow::write_parquet(
    dplyr::tibble(YEAR = c(2020L, 2020L), Hosp_Nis = c(201L, 202L),
      AGE = c(65L, 30L)),
    file.path(path, "NIS_2020.parquet")
  )

  arrow_query <- nis_open(path, years = 2020L)
  duckdb_query <- nis_open(path, years = 2020L, engine = "duckdb")
  expect_s3_class(duckdb_query, "tbl_duckdb_connection")
  expect_true(all(c("YEAR", "HOSP_NIS") %in% colnames(duckdb_query)))
  expect_false("Hosp_Nis" %in% colnames(duckdb_query))

  arrow_result <- arrow_query |>
    dplyr::filter(AGE >= 50) |>
    dplyr::summarise(n = dplyr::n(), hospitals = dplyr::n_distinct(HOSP_NIS)) |>
    dplyr::collect()
  duckdb_result <- duckdb_query |>
    dplyr::filter(AGE >= 50) |>
    dplyr::summarise(n = dplyr::n(), hospitals = dplyr::n_distinct(HOSP_NIS)) |>
    dplyr::collect()
  expect_equal(duckdb_result, arrow_result)
  expect_equal(duckdb_result$n, 1)
})

test_that("nis_open DuckDB scans Parquet string bytes that are not valid UTF-8", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")

  path <- tempfile("nis-invalid-utf8-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  parquet <- file.path(path, "NIS_2019.parquet")
  arrow::write_parquet(
    dplyr::tibble(YEAR = rep(2019L, 3), NOTE = c(
      "before-unique-marker-after", "valid one", "valid two"
    )),
    parquet, compression = "uncompressed", use_dictionary = FALSE
  )

  bytes <- readBin(parquet, "raw", n = file.info(parquet)$size)
  marker <- charToRaw("unique-marker")
  starts <- which(vapply(seq_len(length(bytes) - length(marker) + 1L),
    function(i) identical(bytes[i:(i + length(marker) - 1L)], marker),
    logical(1)))
  if (length(starts) == 0L) {
    skip("Could not locate the invented string in the Parquet page for byte patching.")
  }
  bytes[starts[[1L]] + 7L] <- as.raw(255L)
  writeBin(bytes, parquet)

  query <- nis_open(path, engine = "duckdb")
  result <- query |>
    dplyr::summarise(n = dplyr::n()) |>
    dplyr::collect()
  expect_equal(result$n, 3)
})

test_that("nis_open shuts down its DuckDB connection after the table is released", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")

  path <- tempfile("nis-duckdb-finalizer-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data.frame(YEAR = 2019L),
    file.path(path, "NIS_2019.parquet"))

  query <- nis_open(path, engine = "duckdb")
  con <- query$src$con
  expect_true(duckdb::dbIsValid(con))
  query <- NULL
  invisible(gc())
  expect_false(duckdb::dbIsValid(con))
})
