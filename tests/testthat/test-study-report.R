test_that("a generated study masks unsupported mortality while reporting supported trends", {
  skip_if_not_installed("rmarkdown")
  skip_if_not_installed("purrr")
  skip_if_not_installed("gtsummary", minimum_version = "2.6.1")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("gt")

  withr::local_options(
    easyNIS.duckdb_config = list(threads = 1L),
    survey.lonely.psu = "fail",
    survey.adjust.domain.lonely = FALSE
  )
  attached <- search()
  withr::defer({
    for (package in setdiff(search(), attached)) {
      detach(package, character.only = TRUE)
    }
  })
  study <- nis_new_study(file.path(withr::local_tempdir(), "report"))
  withr::local_dir(study)
  # Knit the shipped analysis in this process. The assertions are on the
  # generated text and tables, before the final Pandoc conversion.
  output <- rmarkdown::render(
    "analysis.qmd",
    output_format = rmarkdown::html_document(),
    params = list(years = 2019:2020),
    envir = new.env(parent = globalenv()),
    run_pandoc = FALSE,
    quiet = TRUE
  )
  report <- readLines(output, encoding = "UTF-8")
  expect_true(any(grepl("invented inpatient discharges for NIS data years 2019, 2020", report, fixed = TRUE)))
  expect_length(grep('<td headers="discharges"[^>]*>54</td>', report), 2L)
  expect_length(grep('<td headers="weighted_N"[^>]*>62[.]4</td>', report), 2L)
  expect_length(grep('<td headers="mortality"[^>]*>Masked</td>', report), 2L)
  expect_length(grep('<td headers="mean_LOS"[^>]*>5[.]66</td>', report), 2L)
  expect_true(any(grepl("National weights +[|]Pass", report)))
  expect_true(any(grepl("Annual release integrity +[|]Not applicable", report)))
})
