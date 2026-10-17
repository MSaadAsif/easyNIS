test_that("nis_new_study copies the packaged template without overwriting", {
  new_study <- getFromNamespace("nis_new_study", "easyNIS")
  parent <- tempfile("nis-study-")
  target <- file.path(parent, "analysis")

  expect_identical(
    normalizePath(new_study(target), winslash = "/", mustWork = FALSE),
    normalizePath(target, winslash = "/", mustWork = FALSE)
  )
  expect_setequal(
    list.files(target, all.files = TRUE, no.. = TRUE),
    c("_quarto.yml", ".gitignore", "analysis.qmd")
  )
  expect_setequal(
    readLines(file.path(target, ".gitignore")),
    c("docs/", "*_files/", "*_cache/", ".quarto/", "*.html", "*.docx")
  )
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
  analysis <- paste(
    readLines(file.path(template, "analysis.qmd"), encoding = "UTF-8"),
    collapse = "\n"
  )
  combined <- paste(quarto, analysis, sep = "\n")

  expect_match(quarto, "embed-resources: true")
  expect_match(quarto, "output-dir: docs")
  expect_match(quarto, "toc: true")
  expect_match(quarto, "echo: false")
  expect_match(analysis, "data_path: null")
  expect_match(analysis, "years: [2017, 2018, 2019, 2020, 2021, 2022]",
               fixed = TRUE)
  for (section in c("Methods", "Cohort flow", "Table 1", "Outcomes",
                    "Trends by year", "Multivariable models")) {
    expect_match(analysis, paste0("## ", section), fixed = TRUE)
  }
  for (interface in c("library(easyNIS)", "nis_example", "nis_open", "nis_flag_dx",
                      "nis_design", "nis_suppress", "cost_adj",
                      "gtsummary::tbl_svysummary",
                      "gtsummary::as_flex_table", "gt::gt",
                      "survey::svyglm", "factor(YEAR)",
                      "srvyr::survey_mean", "ggplot2::geom_ribbon",
                      "gtsummary::add_p()", "gtsummary::add_overall()")) {
    expect_match(combined, interface, fixed = TRUE)
  }
  expect_match(analysis, "IPTW")
  analysis_raw <- readBin(
    file.path(template, "analysis.qmd"),
    what = "raw",
    n = file.info(file.path(template, "analysis.qmd"))$size
  )
  dua_marker <- c(
    charToRaw("Cells based on "),
    as.raw(c(0xe2, 0x89, 0xa4)),
    charToRaw(paste0(
      "10 unweighted discharges are masked (with the overall cell in the same row); ",
      "review tables for other derivable cells before sharing, ",
      "per the HCUP Data Use Agreement."
    ))
  )
  marker_starts <- seq_len(length(analysis_raw) - length(dua_marker) + 1L)
  expect_true(any(vapply(marker_starts, function(start) {
    identical(
      analysis_raw[start:(start + length(dua_marker) - 1L)],
      dua_marker
    )
  }, logical(1))))
  expect_match(analysis, "experimental pending")
  expect_match(
    analysis,
    "options(survey.lonely.psu = \"adjust\", survey.adjust.domain.lonely = TRUE)",
    fixed = TRUE
  )
  expect_false(grepl("omitted in local-data mode|withheld pending", analysis))
  example_branches <- gregexpr("if (is_example)", analysis, fixed = TRUE)[[1L]]
  expect_equal(sum(example_branches > 0L), 1L)
  expect_match(analysis, "gtsummary::tbl_regression(", fixed = TRUE)
  expect_match(analysis, "exponentiate = outcomes$exponentiate[[i]]", fixed = TRUE)
  expect_match(analysis, "split(seq_len(nrow(outcomes)), outcomes$family)", fixed = TRUE)
  expect_match(analysis, "tbls = model_tables[rows]", fixed = TRUE)
  expect_false(grepl("heart[- ]failure|cardiac", combined, ignore.case = TRUE))
  expect_true(regexpr("nis_design(", analysis, fixed = TRUE) <
              regexpr("filter(", analysis, fixed = TRUE))
  drive_roots <- paste0(c(LETTERS, letters), ":", intToUtf8(92))
  expect_false(any(vapply(drive_roots, grepl, logical(1), x = combined,
                          fixed = TRUE)))
  expect_false(grepl("/Users/|/home/|/private/", combined))
})
