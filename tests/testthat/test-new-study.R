test_that("nis_new_study copies the packaged template byte for byte", {
  parent <- tempfile("nis-study-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  target <- file.path(parent, "nested", "analysis")
  template <- system.file("templates", "nis-study", package = "easyNIS")

  expect_identical(
    normalizePath(easyNIS::nis_new_study(target), winslash = "/", mustWork = FALSE),
    normalizePath(target, winslash = "/", mustWork = FALSE)
  )
  expected <- c("_quarto.yml", "analysis.qmd", ".gitignore")
  expect_setequal(list.files(target, all.files = TRUE, no.. = TRUE), expected)

  for (file in c("_quarto.yml", "analysis.qmd")) {
    expect_identical(
      readBin(file.path(target, file), "raw", n = file.info(file.path(target, file))$size),
      readBin(file.path(template, file), "raw", n = file.info(file.path(template, file))$size)
    )
  }
  expect_identical(
    readBin(file.path(target, ".gitignore"), "raw",
            n = file.info(file.path(target, ".gitignore"))$size),
    readBin(file.path(template, "gitignore"), "raw",
            n = file.info(file.path(template, "gitignore"))$size)
  )
})

test_that("nis_new_study preserves occupied destinations", {
  parent <- tempfile("nis-study-occupied-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  target <- file.path(parent, "analysis")
  dir.create(target, recursive = TRUE)
  writeLines("keep me", file.path(target, "sentinel.txt"))

  expect_error(easyNIS::nis_new_study(target), "already exists")
  expect_identical(readLines(file.path(target, "sentinel.txt")), "keep me")

  file_target <- file.path(parent, "occupied-file")
  writeLines("also keep me", file_target)
  expect_error(easyNIS::nis_new_study(file_target), "already exists")
  expect_identical(readLines(file_target), "also keep me")
})

test_that("nis_new_study validates path arguments with stable conditions", {
  expect_invalid_path <- function(path) {
    error <- tryCatch(easyNIS::nis_new_study(path), error = identity)
    expect_s3_class(error, "rlang_error")
    expect_identical(conditionMessage(error),
                     "`path` must be one non-empty directory path.")
    expect_identical(conditionCall(error), quote(easyNIS::nis_new_study(path)))
  }

  expect_invalid_path(NA_character_)
  expect_invalid_path("")
  expect_invalid_path(" \t ")
  expect_invalid_path(character())
  expect_invalid_path(c("one", "two"))
  expect_invalid_path(1)
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
  expect_match(analysis, "split(valid_models, outcomes$family[valid_models])", fixed = TRUE)
  expect_match(analysis, "tbls = model_tables[as.character(rows)]", fixed = TRUE)
  expect_match(analysis, "nis_study_fit_model(", fixed = TRUE)
  expect_match(analysis, "knitr::knit_print(table)", fixed = TRUE)
  expect_match(analysis, "if (!has_cohort)", fixed = TRUE)
  expect_match(analysis, "length(params$years) > 1L", fixed = TRUE)
  expect_match(analysis, "nis_study_cache_key(", fixed = TRUE)
  expect_match(analysis, "nis_study_report_cache_key(", fixed = TRUE)
  expect_match(analysis, 'knitr::knit_code$get("definitions")', fixed = TRUE)
  expect_match(analysis, "YEAR = as.character(YEAR)", fixed = TRUE)
  expect_match(analysis, "`Discharge year` = YEAR", fixed = TRUE)
  expect_false(grepl("heart[- ]failure|cardiac", combined, ignore.case = TRUE))
  expect_true(regexpr("nis_design(", analysis, fixed = TRUE) <
              regexpr("filter(", analysis, fixed = TRUE))
  drive_roots <- paste0(c(LETTERS, letters), ":", intToUtf8(92))
  expect_false(any(vapply(drive_roots, grepl, logical(1), x = combined,
                          fixed = TRUE)))
  expect_false(grepl("/Users/|/home/|/private/", combined))
})

test_that("study model preflight describes empty, sparse, and unstable inputs", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  expect_match(model_status(data.frame(), "outcome", "exposed"), "no rows")
  expect_match(
    model_status(data.frame(outcome = 0:2, exposed = FALSE), "outcome", "exposed"),
    "fewer than two observed levels"
  )
  expect_match(
    model_status(data.frame(outcome = 1, exposed = c(FALSE, TRUE)), "outcome", "exposed"),
    "fewer than two observed values"
  )
  expect_match(
    model_status(data.frame(outcome = c(0, 1), exposed = c(FALSE, TRUE), x = c(1, Inf)),
                 "outcome", "exposed", outcome ~ exposed + x),
    "non-finite values on complete-case rows"
  )
  expect_match(
    model_status(data.frame(outcome = c(0, 1, 0, 1), exposed = c(FALSE, TRUE, FALSE, TRUE),
                            x = c(1, 2, 1, 2)),
                 "outcome", "exposed", outcome ~ exposed + x),
    "rank-deficient"
  )
  expect_null(model_status(
    data.frame(outcome = c(0, 1, NA), exposed = c(FALSE, TRUE, TRUE)),
    "outcome", "exposed"
  ))
})

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
      input_path = path, is_example = FALSE, data_files = file,
      years = 2017:2018, codes = list(dx = "I50"), cohort = "dx & AGE >= 18",
      annualize = FALSE,
      source_chunks = list(setup = 'options(survey.lonely.psu = "adjust")',
                           definitions = definition),
      survey_options = list(lonely_psu = "adjust", adjust_domain_lonely = TRUE)
    )
  }
  key_a <- make(data_a, file_a)
  key_b <- make(data_b, file_b)
  expect_false(identical(key_a$data, key_b$data))
  expect_false(identical(key_a, make(data_a, file_a, "x <- x + 2L")))
  expect_identical(key_a, make(data_a, file_a, "# comment\nx <- x + 1L"))
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
    gtsummary = "2.1.0", gt = "<not-installed>"
  )
  updated <- do.call(make_key, c(updated_args, list(output_format = "html")))
  expect_false(identical(html, docx))
  expect_false(identical(html, updated))
})

coef.study_fit_test <- function(object, ...) c(`(Intercept)` = 1, exposed = 0.5)
vcov.study_fit_test <- function(object, ...) diag(2)
coef.study_bad_coef <- function(object, ...) c(`(Intercept)` = NA_real_)
vcov.study_bad_coef <- function(object, ...) matrix(1)
coef.study_bad_vcov <- function(object, ...) c(`(Intercept)` = 1)
vcov.study_bad_vcov <- function(object, ...) matrix(Inf)
registerS3method("coef", "study_fit_test", coef.study_fit_test,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_fit_test", vcov.study_fit_test,
                 envir = asNamespace("stats"))
registerS3method("coef", "study_bad_coef", coef.study_bad_coef,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_bad_coef", vcov.study_bad_coef,
                 envir = asNamespace("stats"))
registerS3method("coef", "study_bad_vcov", coef.study_bad_vcov,
                 envir = asNamespace("stats"))
registerS3method("vcov", "study_bad_vcov", vcov.study_bad_vcov,
                 envir = asNamespace("stats"))
study_original_file_copy <- base::file.copy
study_original_dir_exists <- base::dir.exists
study_original_dir_create <- base::dir.create

test_that("study model fitting reports successful, failed, and unstable fits", {
  fit_model <- getFromNamespace("nis_study_fit_model", "easyNIS")
  design <- list(variables = data.frame(
    y = c(0, 1, 0, 1), exposed = c(0, 1, 0, 1), x = c(1, 2, 2, 1)
  ))
  formula <- y ~ exposed + x
  fitted <- structure(list(converged = TRUE), class = "study_fit_test")
  fit_ok <- function(...) fitted

  success <- fit_model(formula, design, stats::gaussian(), fit = fit_ok,
                       outcome = "y", exposure = "exposed")
  expect_identical(success$model, fitted)
  expect_null(success$status)
  expect_identical(success$warnings, character())

  fit_error <- function(...) stop("synthetic fit failure")
  failed <- fit_model(formula, design, stats::gaussian(), fit = fit_error)
  expect_null(failed$model)
  expect_identical(failed$status, "Model fit failed: synthetic fit failure")
  expect_identical(failed$warnings, character())

  not_converged <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    structure(list(converged = FALSE), class = "study_fit_test")
  })
  expect_null(not_converged$model)
  expect_identical(not_converged$status, "The model did not converge.")

  benign <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    warning("synthetic benign warning")
    fitted
  })
  expect_identical(benign$model, fitted)
  expect_null(benign$status)
  expect_identical(benign$warnings, "synthetic benign warning")

  material <- fit_model(formula, design, stats::gaussian(), fit = function(...) {
    warning("synthetic fit did not converge")
    fitted
  })
  expect_null(material$model)
  expect_match(material$status, "model fit is unstable")
  expect_identical(material$warnings, "synthetic fit did not converge")
})

test_that("study model fitting rejects invalid coefficient and covariance estimates", {
  fit_model <- getFromNamespace("nis_study_fit_model", "easyNIS")
  design <- list(variables = data.frame(y = 0:3, exposed = c(0, 1, 0, 1)))
  formula <- y ~ exposed
  expect_error_methods <- function(model, expected) {
    result <- fit_model(formula, design, stats::gaussian(), fit = function(...) model)
    expect_null(result$model)
    expect_identical(result$status, expected)
    expect_identical(result$warnings, character())
  }
  expect_error_methods(structure(list(converged = TRUE, bad = "coef"),
                                class = "study_bad_coef"),
                       "The model returned missing or non-finite coefficients.")
  expect_error_methods(structure(list(converged = TRUE, bad = "vcov"),
                                class = "study_bad_vcov"),
                       "The model returned missing or non-finite covariance estimates.")
})

test_that("study model formula preflight handles complete cases and invalid specifications", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  valid <- data.frame(y = c(0, 1, 0, NA), exposed = c(0, 1, 0, 1), x = c(1, 2, 3, 4))
  expect_null(model_status(valid, "y", "exposed", y ~ exposed + x))

  expect_match(model_status(valid, "y", "exposed", y ~ absent), "fails on complete-case rows")
  no_complete_cases <- data.frame(y = c(0, 1), exposed = c(0, 1), x = c(NA, NA))
  expect_match(model_status(no_complete_cases, "y", "exposed", y ~ exposed + x),
               "no complete-case rows")

  # Inject a QR failure to exercise the otherwise difficult rank-evaluation boundary.
  testthat::local_mocked_bindings(
    qr = function(...) stop("synthetic QR failure"), .package = "base"
  )
  expect_match(model_status(valid, "y", "exposed", y ~ exposed + x),
               "rank could not be evaluated")
})

test_that("study model preflight describes missing data and non-finite values", {
  model_status <- getFromNamespace("nis_study_model_data_status", "easyNIS")
  expect_match(model_status(NULL, "y", "exposed"), "unavailable")
  expect_match(model_status(data.frame(y = 0:1), "y", "exposed"), "missing exposed")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, Inf)),
                            "y", "exposed", y ~ exposed), "non-finite")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, Inf)),
                            "y", "exposed"), "exposure exposed contains non-finite")
  expect_match(model_status(data.frame(y = c(0, 1), exposed = c(0, 1),
                                       x = c(Inf, 1)), "y", "exposed", y ~ exposed + x),
               "non-finite values on complete-case rows")
})

test_that("study scaffold reports parent creation failure", {
  parent <- tempfile("nis-scaffold-fault-")
  on.exit(unlink(parent), add = TRUE)
  writeLines("not a directory", parent)
  error <- tryCatch(easyNIS::nis_new_study(file.path(parent, "study")), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "Could not create the parent directory")
  expect_true(file.exists(parent))
})

test_that("study scaffold reports destination creation failure", {
  parent <- tempfile("nis-scaffold-fault-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  dir.create(parent)
  destination <- file.path(parent, "study")
  create_calls <- 0L
  testthat::local_mocked_bindings(
    dir.create = function(path, ...) {
      create_calls <<- create_calls + 1L
      if (create_calls == 1L) FALSE else study_original_dir_create(path, ...)
    },
    .package = "base"
  )
  expect_error(easyNIS::nis_new_study(destination), "Could not create the study directory")
  expect_false(dir.exists(destination))
})

test_that("study scaffold removes partial destination when template is unavailable", {
  parent <- tempfile("nis-scaffold-fault-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  destination <- file.path(parent, "study")
  template <- system.file("templates", "nis-study", package = "easyNIS")
  testthat::local_mocked_bindings(
    dir.exists = function(path, ...) {
      if (identical(path, template)) FALSE else study_original_dir_exists(path, ...)
    },
    .package = "base"
  )
  expect_error(easyNIS::nis_new_study(destination), "template is unavailable")
  expect_false(dir.exists(destination))
})

test_that("study scaffold removes partial destination after copy failure", {
  parent <- tempfile("nis-scaffold-fault-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  destination <- file.path(parent, "study")
  testthat::local_mocked_bindings(
    file.copy = function(from, to, ...) {
      study_original_file_copy(from[[1]], to, ...)
      FALSE
    },
    .package = "base"
  )
  expect_error(easyNIS::nis_new_study(destination), "Could not copy the packaged")
  expect_false(dir.exists(destination))
})

test_that("study scaffold removes copied files after gitignore rename failure", {
  parent <- tempfile("nis-scaffold-fault-")
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  destination <- file.path(parent, "study")
  testthat::local_mocked_bindings(file.rename = function(...) FALSE, .package = "base")
  expect_error(easyNIS::nis_new_study(destination), "Could not create the study output")
  expect_false(dir.exists(destination))
})
