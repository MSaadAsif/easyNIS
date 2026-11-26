test_that("study cache keys change when definitions or external data roots change", {
  make_key <- getFromNamespace("nis_study_cache_key", "easyNIS")
  root <- tempfile("nis-cache-key-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  data_a <- file.path(root, "a")
  data_b <- file.path(root, "b")
  dir.create(data_a)
  dir.create(data_b)
  file_a <- file.path(data_a, "part.parquet")
  file_b <- file.path(data_b, "part.parquet")
  writeBin(as.raw(1:4), file_a)
  writeBin(as.raw(c(1, 2, 3, 5)), file_b)
  fixed_time <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")
  Sys.setFileTime(file_a, fixed_time)
  Sys.setFileTime(file_b, fixed_time)
  make <- function(path, file, definition = "x <- x + 1L") {
    make_key(
      input_path = path,
      is_example = FALSE,
      data_files = file,
      years = 2017:2018,
      codes = list(dx = "I50"),
      cohort = "dx & AGE >= 18",
      annualize = FALSE,
      source_chunks = list(setup = 'options(survey.lonely.psu = "adjust")', definitions = definition),
      survey_options = list(lonely_psu = "adjust", adjust_domain_lonely = TRUE)
    )
  }
  key_a <- make(data_a, file_a)
  key_b <- make(data_b, file_b)
  expect_false(identical(key_a$data, key_b$data))
  expect_false(identical(key_a, make(data_a, file_a, "x <- x + 2L")))
  expect_identical(key_a, make(data_a, file_a, "# comment\nx <- x + 1L"))
  withr::local_options(easyNIS.duckdb_config = list(threads = 2L))
  expect_false(identical(key_a, make(data_a, file_a)))
})

test_that("study cache keys track selected Parquet parts only", {
  path <- nis_example(2019:2020)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  selected <- nis_open(path, years = 2020L)
  make_key <- function() {
    nis_study_cache_key(
      input_path = path,
      is_example = FALSE,
      data_files = nis_open_source_paths(selected),
      years = 2020L,
      codes = list(dx = "I50"),
      cohort = "dx",
      annualize = FALSE,
      source_chunks = list(),
      survey_options = list()
    )
  }
  input_key <- make_key()
  unselected_part <- file.path(path, "NIS_2019.parquet", "part-0.parquet")
  selected_part <- file.path(path, "NIS_2020.parquet", "part-0.parquet")
  updated_time <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")

  expect_true(Sys.setFileTime(unselected_part, updated_time))
  expect_identical(make_key(), input_key)
  expect_true(Sys.setFileTime(selected_part, updated_time))
  expect_false(identical(make_key(), input_key))
})

test_that("report cache keys include model inputs, format, and dependency versions", {
  make_key <- getFromNamespace("nis_study_report_cache_key", "easyNIS")
  design <- list(cache_key = "design")
  args <- list(
    design_key = design,
    exposure = "exposed",
    covariates = c("AGE", "factor(YEAR)"),
    outcomes = data.frame(outcome = "DIED", family = "quasibinomial"),
    package_versions = c(gtsummary = "2.0.0", gt = "<not-installed>")
  )
  html <- do.call(make_key, c(args, list(output_format = "html")))
  docx <- do.call(make_key, c(args, list(output_format = "docx")))
  updated_args <- args
  updated_args$package_versions <- c(
    gtsummary = "2.1.0",
    gt = "<not-installed>"
  )
  updated <- do.call(make_key, c(updated_args, list(output_format = "html")))
  expect_false(identical(html, docx))
  expect_false(identical(html, updated))
})
