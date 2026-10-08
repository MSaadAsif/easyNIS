source(file.path("..", "layout-metadata.R"), local = TRUE)

invented_layout <- function(year = 2022L, revision = "unspecified", legacy = FALSE) {
  dataset <- paste0("NIS_", year, "_CORE", if (revision == "V2") "_V2" else "")
  ranges <- if (legacy) list(c(1,3), c(5,8), c(10,35), c(37,39), c(41,69),
                            c(71,73), c(75,77), c(79,79), c(81,84)) else
    list(c(1,3), c(5,8), c(10,35), c(37,40), c(42,70),
         c(72,75), c(77,80), c(82,82), c(84,87))
  descriptions <- c("Database name", "Discharge year of data", "File name",
    "Data element number", "Data element name",
    "Starting column of data element in ASCII file", "Ending column of data element in ASCII file",
    "Non-zero number of digits after decimal point for numeric data element",
    "Data element type (Num=numeric; Char=character)")
  guide <- vapply(seq_along(ranges), function(i) {
    paste0(sprintf("%2d-%3d    ", ranges[[i]][1L], ranges[[i]][2L]), descriptions[i])
  }, character(1))
  names <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "I10_DX1", "I10_PR1")
  widths <- c(4L, 10L, 5L, 4L, 11L, 7L, 7L)
  ends <- cumsum(widths)
  starts <- ends - widths + 1L
  rows <- vapply(seq_along(names), function(i) {
    values <- c("NIS", as.character(year), dataset, as.character(i), names[i],
                as.character(starts[i]), as.character(ends[i]), if (i == 5L) "7" else "",
                if (i <= 5L) "Num" else "Char")
    line <- strrep(" ", 100L)
    for (j in seq_along(values)) {
      substring(line, ranges[[j]][1L], ranges[[j]][2L]) <-
        sprintf(paste0("%-", diff(ranges[[j]]) + 1L, "s"), values[j])
    }
    line
  }, character(1))
  c(paste("Data Set Name:", dataset), "Number of Observations: 12",
    paste("Total Record Length:", sum(widths)), "Total Number of Data Elements: 7", guide, rows)
}

test_that("column guides handle both formatting eras using invented facts", {
  for (legacy in c(FALSE, TRUE)) {
    layout <- parse_core_layout(invented_layout(2017L, legacy = legacy), 2017L)
    expect_identical(layout$records, 12L)
    expect_identical(layout$record_length, 48L)
    expect_identical(layout$fields$name, c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM",
                                        "DISCWT", "I10_DX1", "I10_PR1"))
    expect_identical(layout$fields$decimals, c(0L, 0L, 0L, 0L, 7L, 0L, 0L))
    expect_identical(layout$diagnosis_slots, 1L)
    expect_identical(layout$procedure_slots, 1L)
  }
  expect_identical(parse_core_layout(invented_layout(2019L, "V2"), 2019L, "V2")$dataset,
                   "NIS_2019_CORE_V2")
})

test_that("wrong years, revisions and incomplete headers cannot create registry facts", {
  lines <- invented_layout()
  expect_error(parse_core_layout(lines, 2021L), "wrong dataset")
  expect_error(parse_core_layout(invented_layout(2019L), 2019L, "V2"), "wrong dataset")
  expect_error(parse_core_layout(c(lines, lines[1L]), 2022L), "repeated")
  expect_error(parse_core_layout(lines[-2L], 2022L), "missing")
  expect_error(parse_core_layout(sub("Observations: 12", "Observations: 1.2", lines), 2022L),
               "whole number")
  expect_error(parse_core_layout(sub("Observations: 12", "Observations: 999999999999", lines), 2022L),
               "parser limit")
  expect_error(parse_core_layout(sub("Observations: 12", "Observations: 0", lines), 2022L), "empty")
  expect_error(parse_core_layout(lines[-length(lines)], 2022L), "field count")
  expect_error(parse_core_layout(sub("NIS 2022", "NIS 2021", lines), 2022L), "wrong dataset or year")
  expect_error(parse_core_layout(sub("Total Record Length: 48", "Total Record Length: 49", lines), 2022L),
               "record positions")
})

test_that("field damage is rejected before facts are accepted", {
  lines <- invented_layout()
  change <- function(row, first, last, value) {
    altered <- lines
    substring(altered[13L + row], first, last) <-
      sprintf(paste0("%-", last - first + 1L, "s"), value)
    altered
  }
  expect_error(parse_core_layout(change(2L, 37L, 40L, "1"), 2022L), "field numbers")
  expect_error(parse_core_layout(change(2L, 42L, 70L, "year"), 2022L), "duplicated")
  expect_error(parse_core_layout(change(2L, 42L, 70L, "BAD-NAME"), 2022L), "field names")
  expect_error(parse_core_layout(change(2L, 84L, 87L, "Bool"), 2022L), "field type")
  expect_error(parse_core_layout(change(2L, 72L, 75L, "6"), 2022L), "record positions")
  expect_error(parse_core_layout(change(2L, 82L, 82L, "1"), 2022L), "structural fields")
  expect_error(parse_core_layout(change(1L, 84L, 87L, "Char"), 2022L), "structural fields")
  expect_error(parse_core_layout(change(1L, 42L, 70L, "OTHER_YEAR"), 2022L), "structural fields")
  expect_error(parse_core_layout(change(6L, 82L, 82L, "1"), 2022L), "decimal precision")
  expect_error(parse_core_layout(change(6L, 42L, 70L, "I10_DX2"), 2022L), "coding slots")
  expect_error(parse_core_layout(change(6L, 84L, 87L, "Num"), 2022L), "coding slots")
  expect_error(parse_core_layout(lines[-5L], 2022L), "column guide")
  truncated <- lines
  truncated[length(truncated)] <- substr(truncated[length(truncated)], 1L, 85L)
  expect_error(parse_core_layout(truncated, 2022L), "truncated")
  overlapping <- sub("42- 70", "39- 70", lines, fixed = TRUE)
  expect_error(parse_core_layout(overlapping, 2022L), "overlapping")
  shorter_code <- change(7L, 77L, 80L, "47")
  shorter_code <- sub("Total Record Length: 48", "Total Record Length: 47", shorter_code)
  expect_error(parse_core_layout(shorter_code, 2022L), "coding slots")
})

test_that("failed retrieval or parsing preserves the existing registry", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  output <- file.path(directory, "registry.csv")
  cache <- file.path(directory, "cache")
  writeLines("existing registry", output)
  old <- readBin(output, "raw", n = file.info(output)$size)
  timeout <- getOption("timeout")
  fail_download <- function(url, path) { writeLines("partial download", path); 1L }
  expect_error(update_layout_metadata(2022L, cache, output, download = fail_download), "download failed")
  expect_identical(list.files(cache, all.files = FALSE), character())
  expect_identical(getOption("timeout"), timeout)
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  bad_download <- function(url, path) { writeLines(invented_layout(2021L), path); 0L }
  expect_error(update_layout_metadata(2022L, cache, output, download = bad_download), "wrong dataset")
  expect_identical(list.files(cache), character())
  good_download <- function(url, path) { writeLines(invented_layout(), path); 0L }
  expect_error(update_layout_metadata(c(2021L, 2022L), cache, output, download = good_download),
               "wrong dataset")
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  expect_error(update_layout_metadata(2022L, cache, output, cached_only = TRUE), "Missing cached")
  partial_batch <- function(url, path) {
    writeLines(invented_layout(2017L, legacy = TRUE), path)
    0L
  }
  expect_error(update_layout_metadata(c(2017L, 2018L), cache, output, download = partial_batch),
               "wrong dataset")
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  expect_identical(list.files(cache), "FileSpecifications_NIS_2017_Core.TXT")
})

test_that("validated cache refresh is offline and remains provisional", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  cache <- file.path(directory, "cache")
  output <- file.path(directory, "registry.csv")
  download <- function(url, path) { writeLines(invented_layout(), path); 0L }
  result <- update_layout_metadata(2022L, cache, output, download = download)
  expect_identical(result$review_status, "provisional")
  expect_identical(result$core_records, 12L)
  expect_identical(result$documented_revision, "unspecified")
  expect_match(result$source_md5, "^[a-f0-9]{32}$")
  expect_true(file.exists(file.path(cache, "FileSpecifications_NIS_2022_Core.TXT")))
  expect_equal(utils::read.csv(output)$core_records, 12L)
  no_download <- function(...) stop("Unexpected network access")
  refreshed <- update_layout_metadata(2022L, cache, output, TRUE, no_download)
  expect_identical(refreshed$source_md5, result$source_md5)
  expect_identical(refreshed$core_records, result$core_records)
  cached <- file.path(cache, "FileSpecifications_NIS_2022_Core.TXT")
  writeLines("truncated cache", cached)
  old <- readLines(output)
  expect_error(update_layout_metadata(2022L, cache, output, TRUE, no_download), "Invalid Core")
  expect_identical(readLines(output), old)
})
