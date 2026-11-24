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

  missing <- tryCatch(easyNIS::nis_new_study(), error = identity)
  expect_identical(
    conditionMessage(missing),
    "argument \"path\" is missing, with no default"
  )
  expect_identical(conditionCall(missing), quote(easyNIS::nis_new_study()))
})

test_that("the packaged Quarto template contains no private paths", {
  template <- system.file("templates", "nis-study", package = "easyNIS")
  files <- file.path(template, c("_quarto.yml", "analysis.qmd"))
  combined <- unlist(lapply(files, readLines, encoding = "UTF-8"))
  drive_roots <- paste0(c(LETTERS, letters), ":", intToUtf8(92))
  expect_false(any(vapply(drive_roots, function(root) {
    any(grepl(root, combined, fixed = TRUE))
  }, logical(1))))
  expect_false(any(grepl("/Users/|/home/|/private/", combined)))
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
  normalized <- normalizePath(destination, winslash = "/", mustWork = FALSE)
  create_dir <- base::dir.create
  testthat::local_mocked_bindings(
    dir.create = function(path, ...) {
      if (identical(path, normalized)) FALSE else create_dir(path, ...)
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
  exists_dir <- base::dir.exists
  testthat::local_mocked_bindings(
    dir.exists = function(path, ...) {
      if (identical(path, template)) FALSE else exists_dir(path, ...)
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
  normalized <- normalizePath(destination, winslash = "/", mustWork = FALSE)
  copy_file <- base::file.copy
  testthat::local_mocked_bindings(
    file.copy = function(from, to, ...) {
      if (!identical(to, normalized)) return(copy_file(from, to, ...))
      copy_file(from[[1]], to, ...)
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


test_that("relative scaffold paths return their normalized destinations", {
  root <- tempfile("nis-study-relative-")
  dir.create(root)
  withr::defer(unlink(root, recursive = TRUE))
  withr::local_dir(root)
  study <- nis_new_study(file.path(".", "study"))
  expect_identical(study, normalizePath("study", winslash = "/", mustWork = TRUE))
})
