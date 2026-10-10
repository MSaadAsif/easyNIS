inventory_tool <- new.env(parent = globalenv())
sys.source(file.path("..", "inventory-parquet.R"), envir = inventory_tool)

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
  for (path in paths) {
    DBI::dbExecute(con, paste0("COPY (SELECT 1 AS invented_id, 'not-a-record' AS invented_text) TO ",
      DBI::dbQuoteString(con, path), " (FORMAT PARQUET)"))
  }
  writer <- vapply(paths, function(path) {
    DBI::dbGetQuery(con, paste0("SELECT created_by FROM parquet_file_metadata(",
      DBI::dbQuoteString(con, path), ")"))$created_by
  }, character(1), USE.NAMES = FALSE)
  expect_output(inventory_tool$main(c(input, output)), "Inventoried 2 parquet files")
  receipt <- utils::read.csv(file.path(output, "file-inventory.csv"), stringsAsFactors = FALSE)
  expect_identical(receipt$writer_metadata, writer)
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
