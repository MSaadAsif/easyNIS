test_that("nis_new_study copies the packaged template without overwriting", {
  new_study <- getFromNamespace("nis_new_study", "easyNIS")
  parent <- tempfile("nis-study-")
  target <- file.path(parent, "analysis")

  expect_identical(new_study(target), normalizePath(target, winslash = "/"))
  expect_setequal(list.files(target), c("_quarto.yml", "analysis.qmd"))
  writeLines("keep me", file.path(target, "sentinel.txt"))

  expect_error(new_study(target), "already exists")
  expect_identical(readLines(file.path(target, "sentinel.txt")), "keep me")

  unlink(parent, recursive = TRUE)
})

test_that("nis_new_study rejects invalid and occupied destinations", {
  new_study <- getFromNamespace("nis_new_study", "easyNIS")
  expect_error(new_study(NA_character_), "one non-empty")
  expect_error(new_study(""), "one non-empty")

  parent <- tempfile("nis-study-file-")
  dir.create(parent)
  target <- file.path(parent, "occupied")
  writeLines("keep me", target)
  expect_error(new_study(target), "already exists")
  expect_identical(readLines(target), "keep me")
  unlink(parent, recursive = TRUE)
})

test_that("the packaged Quarto template follows the scaffold contract", {
  template <- system.file("templates", "nis-study", package = "easyNIS")
  expect_true(file.exists(file.path(template, "_quarto.yml")))
  expect_true(file.exists(file.path(template, "analysis.qmd")))
  expect_false(file.exists(file.path(template, "styles.css")))

  quarto <- paste(readLines(file.path(template, "_quarto.yml")), collapse = "\n")
  analysis <- paste(readLines(file.path(template, "analysis.qmd")), collapse = "\n")
  combined <- paste(quarto, analysis, sep = "\n")

  expect_match(quarto, "embed-resources: true")
  expect_match(quarto, "toc: true")
  expect_match(quarto, "echo: false")
  expect_match(analysis, "data_path: null")
  expect_match(analysis, "years: [2017, 2018, 2019, 2020, 2021, 2022]",
               fixed = TRUE)
  for (section in c("Methods", "Cohort flow", "Table 1", "Outcomes",
                    "Trends by year", "Multivariable models")) {
    expect_match(analysis, paste0("## ", section), fixed = TRUE)
  }
  for (interface in c("nis_example", "nis_open", "nis_flag_dx",
                      "nis_flag_pr", "nis_design", "nis_label", "nis_cost",
                      "nis_suppress", "gtsummary::tbl_svysummary",
                      "gtsummary::as_flex_table", "gt::gt",
                      "survey::svyglm", "factor(YEAR)")) {
    expect_match(combined, interface, fixed = TRUE)
  }
  expect_match(analysis, "IPTW")
  expect_match(analysis, "scientifically validated")
  expect_match(analysis, "regression tables are withheld")
  expect_match(analysis, "tbl_regression(model, exponentiate = FALSE)",
               fixed = TRUE)
  expect_false(grepl("heart[- ]failure|cardiac", combined, ignore.case = TRUE))
  expect_true(regexpr("nis_design(", analysis, fixed = TRUE) <
              regexpr("filter(", analysis, fixed = TRUE))
  drive_roots <- paste0(c(LETTERS, letters), ":", intToUtf8(92))
  expect_false(any(vapply(drive_roots, grepl, logical(1), x = combined,
                          fixed = TRUE)))
  expect_false(grepl("/Users/|/home/|/private/", combined))
})
