source(file.path("..", "layout-metadata.R"), local = TRUE)

invented_layout <- function(year = 2022L, revision = "unspecified", legacy = FALSE,
                            component = "Core") {
  dataset <- paste0("NIS_", year, "_", toupper(component), if (revision == "V2") "_V2" else "")
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
  names <- switch(component,
    Core = c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "I10_DX1", "I10_PR1"),
    Hospital = c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT"),
    Severity = c("HOSP_NIS", "KEY_NIS", "TEST_SCORE"),
    DX_PR_GRPS = c("HOSP_NIS", "KEY_NIS", "TEST_VERSION", "TEST_GROUP"))
  widths <- unname(c(YEAR = 4L, KEY_NIS = 10L, HOSP_NIS = 5L, NIS_STRATUM = 4L,
    DISCWT = 11L, I10_DX1 = 7L, I10_PR1 = 7L, TEST_SCORE = 2L,
    TEST_VERSION = 6L, TEST_GROUP = 1L)[names])
  ends <- cumsum(widths)
  starts <- ends - widths + 1L
  rows <- vapply(seq_along(names), function(i) {
    values <- c("NIS", as.character(year), dataset, as.character(i), names[i],
                as.character(starts[i]), as.character(ends[i]), if (names[i] == "DISCWT") "7" else "",
                if (names[i] %in% c("I10_DX1", "I10_PR1", "TEST_VERSION")) "Char" else "Num")
    line <- strrep(" ", 100L)
    for (j in seq_along(values)) {
      substring(line, ranges[[j]][1L], ranges[[j]][2L]) <-
        sprintf(paste0("%-", diff(ranges[[j]]) + 1L, "s"), values[j])
    }
    line
  }, character(1))
  c(paste("Data Set Name:", dataset), "Number of Observations: 12",
    paste("Total Record Length:", sum(widths)), paste("Total Number of Data Elements:", length(names)), guide, rows)
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
  expect_identical(parse_core_layout(invented_layout(2019L), 2019L)$dataset,
                   "NIS_2019_CORE")
})

test_that("wrong datasets, years and incomplete headers cannot create registry facts", {
  lines <- invented_layout()
  expect_error(parse_core_layout(lines, 2021L), "wrong dataset")
  expect_error(parse_core_layout(invented_layout(2019L, "V2"), 2019L), "wrong dataset")
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
  expect_identical(result$specification_revision, "unspecified")
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

test_that("V2 specification filenames retain unsuffixed dataset identities", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  requested <- character()
  download <- function(url, path) {
    requested <<- c(requested, url)
    year <- if (grepl("2019", url, fixed = TRUE)) 2019L else 2020L
    writeLines(invented_layout(year), path)
    0L
  }
  result <- update_layout_metadata(c(2019L, 2020L), file.path(directory, "cache"),
    file.path(directory, "registry.csv"), download = download)
  expect_identical(result$year, c(2019L, 2020L))
  expect_identical(result$specification_revision, c("V2", "V2"))
  expect_identical(result$dataset_name, c("NIS_2019_CORE", "NIS_2020_CORE"))
  expect_true(all(grepl("_Core_V2.TXT", requested, fixed = TRUE)))
  expect_identical(result$review_status, c("provisional", "provisional"))
  expect_identical(result$core_records, c(12L, 12L))
  expect_false("documented_revision" %in% names(result))
  refreshed <- update_layout_metadata(c(2019L, 2020L), file.path(directory, "cache"),
    file.path(directory, "registry.csv"), cached_only = TRUE,
    download = function(...) stop("Unexpected network request"))
  expect_identical(refreshed$source_md5, result$source_md5)
  expect_identical(refreshed$dataset_name, result$dataset_name)
  expect_identical(refreshed$specification_revision, result$specification_revision)
})

invented_component_cache <- function(directory) {
  dir.create(directory)
  for (year in 2017:2022) {
    for (component in c("Core", "Hospital", "Severity", "DX_PR_GRPS")) {
      if (year == 2017L && component == "DX_PR_GRPS") next
      suffix <- if (year %in% c(2019L, 2020L)) "_V2" else ""
      filename <- paste0("FileSpecifications_NIS_", year, "_", component, suffix, ".TXT")
      lines <- invented_layout(year, legacy = year == 2017L, component = component)
      if (component == "Hospital") {
        lines <- sub("Number of Observations: 12", "Number of Observations: 2", lines, fixed = TRUE)
      }
      writeLines(lines, file.path(directory, filename))
    }
  }
}

test_that("component readers retain source fields across both guide eras", {
  for (legacy in c(FALSE, TRUE)) {
    for (component in c("Hospital", "Severity", "DX_PR_GRPS")) {
      lines <- invented_layout(2018L, legacy = legacy, component = component)
      layout <- parse_nis_layout(lines, 2018L, component)
      expect_identical(layout$dataset, paste0("NIS_2018_", toupper(component)))
      expect_identical(layout$records, 12L)
      expect_identical("YEAR" %in% layout$fields$name, component == "Hospital")
      expect_error(parse_nis_layout(lines, 2019L, component), "wrong dataset")
      expect_error(parse_nis_layout(lines, 2018L, "Core"), "wrong dataset")
    }
  }
  bad <- invented_layout(component = "Severity")
  expect_error(parse_nis_layout(sub("KEY_NIS", "KEY_BAD", bad, fixed = TRUE), 2022L, "Severity"),
               "structural fields")
  row <- grep("^NIS ", bad)[2L]
  substring(bad[row], 84L, 87L) <- "Char"
  expect_error(parse_nis_layout(bad, 2022L, "Severity"), "structural fields")
  expect_error(parse_nis_layout(bad, 2022L, "unknown"), "arg")
})

test_that("complete cached component metadata is provisional and preserves absent fields", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  cache <- file.path(directory, "cache")
  invented_component_cache(cache)
  output <- file.path(directory, "components.csv")
  result <- update_component_metadata(cache, output)
  expect_identical(nrow(result), 23L)
  expect_identical(table(result$year) |> as.integer(), c(3L, 4L, 4L, 4L, 4L, 4L))
  expect_false(any(result$year == 2017L & result$component == "DX_PR_GRPS"))
  expect_true(all(result$review_status == "provisional"))
  expect_true(all(result$source_records[result$component == "Hospital"] == 2L))
  expect_true(all(result$source_records[result$component != "Hospital"] == 12L))
  expect_identical(result$has_YEAR, result$component %in% c("Core", "Hospital"))
  expect_identical(result$has_KEY_NIS, result$component != "Hospital")
  expect_true(all(result$has_HOSP_NIS))
  expect_identical(result$has_NIS_STRATUM, result$component %in% c("Core", "Hospital"))
  expect_identical(result$has_DISCWT, result$component %in% c("Core", "Hospital"))
  expect_identical(result$specification_revision == "V2", result$year %in% c(2019L, 2020L))
  expect_true(all(grepl("^https://hcup-us.ahrq.gov/", result$source)))
  expect_identical(result$source_md5, unname(tools::md5sum(file.path(cache, basename(result$source)))))
  refreshed <- update_component_metadata(cache, output)
  expect_identical(refreshed[names(refreshed) != "parsed_utc"], result[names(result) != "parsed_utc"])
  expect_equal(utils::read.csv(output)$source_records, result$source_records)
  expect_identical(list.files(directory), c("cache", "components.csv"))
})

test_that("incomplete or damaged component caches preserve previous registry bytes", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  cache <- file.path(directory, "cache")
  invented_component_cache(cache)
  output <- file.path(directory, "components.csv")
  writeLines("previous registry", output)
  old <- readBin(output, "raw", n = file.info(output)$size)
  last <- file.path(cache, "FileSpecifications_NIS_2022_DX_PR_GRPS.TXT")
  writeLines(invented_layout(2021L, component = "DX_PR_GRPS"), last)
  expect_error(update_component_metadata(cache, output), "wrong dataset")
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  unlink(last)
  expect_error(update_component_metadata(cache, output), "Missing cached specification")
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  writeLines(invented_layout(2022L, component = "DX_PR_GRPS"), last)
  core <- file.path(cache, "FileSpecifications_NIS_2017_Core.TXT")
  writeLines(sub("I10_DX1", "I10_DX2", invented_layout(2017L, legacy = TRUE), fixed = TRUE), core)
  expect_error(update_component_metadata(cache, output), "coding slots")
  expect_identical(readBin(output, "raw", n = file.info(output)$size), old)
  expect_identical(list.files(directory), c("cache", "components.csv"))
})
