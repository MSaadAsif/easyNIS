inventory_tool <- new.env(parent = globalenv())
sys.source(file.path("..", "inventory-parquet.R"), envir = inventory_tool)

test_that("inventory retains physical top-level names despite SQL name repair", {
  directory <- tempfile("invented field names ")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "inputs")
  dir.create(input)
  fields <- c("field", "FIELD", "FIELD_1", "field", "nested", "after")
  values <- list(1:2, c(1.25, 2.5), c("first", "second"), c(TRUE, FALSE),
    data.frame(child = 3:4), c(5, 6))
  names(values) <- fields
  path <- file.path(input, "NIS_2022.parquet")
  arrow::write_parquet(do.call(arrow::Table$create, values), path)
  output <- file.path(directory, "receipts")
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 1 parquet files")
  schema <- utils::read.csv(file.path(output, "schemas.csv"))
  expect_identical(schema$column_name, fields)
  expect_identical(schema$position, seq_along(fields))
  expect_identical(schema$column_type,
    c("INTEGER", "DOUBLE", "VARCHAR", "BOOLEAN", "STRUCT(child INTEGER)", "DOUBLE"))
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"))
  expect_identical(receipt$columns, length(fields))
  cli_output <- file.path(directory, "cli receipts")
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(normalizePath(file.path("..", "inventory-parquet.R"))),
      shQuote(input), shQuote(cli_output)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(status, "status"))
  expect_identical(utils::read.csv(file.path(cli_output, "schemas.csv")), schema)
})

test_that("inventory schemas describe file columns rather than partition folders", {
  directory <- tempfile("invented partition folders ")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "inputs")
  nested <- file.path(input, "YEAR=2017", "invented_partition=west")
  dir.create(nested, recursive = TRUE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  path <- file.path(nested, "NIS_2022.parquet")
  DBI::dbExecute(con, paste0("COPY (SELECT 2022::INTEGER AS YEAR, ",
    "1::INTEGER AS invented_id) TO ", DBI::dbQuoteString(con, path),
    " (FORMAT PARQUET)"))
  output <- file.path(directory, "receipts")
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 1 parquet files")
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"))
  schema <- utils::read.csv(file.path(output, "schemas.csv"))
  expect_identical(receipt$columns, 2L)
  expect_identical(receipt$year_hint, 2022L)
  expect_identical(schema$column_name, c("YEAR", "invented_id"))
  expect_identical(schema$column_type, c("INTEGER", "INTEGER"))
  cli_output <- file.path(directory, "cli receipts")
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(normalizePath(file.path("..", "inventory-parquet.R"))),
      shQuote(input), shQuote(cli_output)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(status, "status"))
  expect_identical(utils::read.csv(file.path(cli_output, "schemas.csv")), schema)
})

test_that("inventory year hints come only from complete parquet basenames", {
  directory <- tempfile("invented year hints ")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "inputs")
  dir.create(input)
  misleading <- file.path(input, "NIS_2020.parquet")
  dir.create(misleading)
  paths <- c(file.path(misleading, "no-year.parquet"),
    file.path(input, c("NIS_2017.parquet", "nis_2018.PARQUET",
      "prefixNIS_2019.parquet", "NIS_2021.parquet.copy.parquet")))
  expected <- c(NA_integer_, 2017L, 2018L, NA_integer_, NA_integer_)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (path in paths) {
    DBI::dbExecute(con, paste0("COPY (SELECT 2022 AS YEAR) TO ",
      DBI::dbQuoteString(con, path), " (FORMAT PARQUET)"))
  }
  output <- file.path(directory, "receipts")
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 5 parquet files")
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"))
  schema <- utils::read.csv(file.path(output, "schemas.csv"))
  normalized <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  expect_identical(receipt$year_hint[match(normalized, receipt$path)], expected)
  expect_identical(schema$year_hint[match(normalized, schema$path)], expected)
  expect_identical(receipt$release_revision, rep("unknown", 5L))
})

test_that("inventory retains writer metadata without authenticating conversion history", {
  directory <- tempfile("invented inventory ")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "inputs")
  output <- file.path(directory, "receipts")
  dir.create(input)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  paths <- file.path(input, c("NIS_2022.parquet", "no-year.parquet"))
  codecs <- c("ZSTD", "SNAPPY")
  for (index in seq_along(paths)) {
    path <- paths[[index]]
    DBI::dbExecute(con, paste0("COPY (SELECT 1 AS invented_id, 'not-a-record' AS invented_text) TO ",
      DBI::dbQuoteString(con, path), " (FORMAT PARQUET, COMPRESSION ", codecs[[index]], ")"))
  }
  writer <- vapply(paths, function(path) {
    DBI::dbGetQuery(con, paste0("SELECT created_by FROM parquet_file_metadata(",
      DBI::dbQuoteString(con, path), ")"))$created_by
  }, character(1), USE.NAMES = FALSE)
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 2 parquet files")
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"), stringsAsFactors = FALSE)
  expect_identical(receipt$writer_metadata, writer)
  expect_identical(receipt$compression_metadata, codecs)
  expect_identical(receipt$year_hint, c(2022L, NA_integer_))
  expect_identical(receipt$rows_from_footer, c(1L, 1L))
  expect_identical(receipt$columns, c(2L, 2L))
  expect_identical(receipt$conversion_provenance, rep("unknown", 2L))
  expect_identical(receipt$release_revision, rep("unknown", 2L))
  expect_identical(receipt$prefiltered, rep("unknown", 2L))
  expect_identical(receipt$labels_preserved, rep("unverified", 2L))
  expect_identical(receipt$missing_reasons_preserved, rep("unverified", 2L))
  notes <- readLines(file.path(output, "README.md"))
  expect_true(any(grepl("not proof of the converter", notes, fixed = TRUE)))
  expect_true(any(grepl("does not establish requested conversion settings", notes, fixed = TRUE)))
  schema <- utils::read.csv(file.path(output, "schemas.csv"), stringsAsFactors = FALSE)
  expect_identical(schema$column_name, rep(c("invented_id", "invented_text"), 2L))
  expect_false(any(grepl("not-a-record", unlist(lapply(list.files(output, full.names = TRUE),
    readLines)), fixed = TRUE)))
  cli_output <- file.path(directory, "cli receipts")
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(normalizePath(file.path("..", "inventory-parquet.R"))),
      shQuote(input), shQuote(cli_output)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(status, "status"))
  expect_true(any(grepl("Inventoried 2 parquet files", status, fixed = TRUE)))
  expect_identical(utils::read.csv(file.path(cli_output, "file-inventory.csv"),
    stringsAsFactors = FALSE), receipt)
})

test_that("inventory combines distinct codecs across column chunks", {
  directory <- tempfile("invented mixed codecs ")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "inputs")
  dir.create(input)
  arrow::write_parquet(data.frame(first = 1:4, second = 5:8, third = 9:12),
    file.path(input, "mixed.parquet"), chunk_size = 2L,
    compression = c(first = "zstd", second = "snappy", third = "zstd"))
  output <- file.path(directory, "receipts")
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 1 parquet files")
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"), stringsAsFactors = FALSE)
  expect_identical(receipt$compression_metadata, "SNAPPY;ZSTD")
  expect_identical(receipt$row_groups, 2L)
})
