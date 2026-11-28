test_that("failed acquisition preserves existing spill and staging directories", {
  parent <- normalizePath(withr::local_tempdir(), winslash = "/", mustWork = TRUE)
  fixture <- nis_example(2020L)
  query <- nis_open(fixture, check_release = FALSE)
  paths <- file.path(parent, c("occupied-spill", "occupied-stage"))
  for (path in paths) {
    dir.create(path)
    writeLines("keep", file.path(path, "sentinel"))
  }
  local_mocked_bindings(nis_owned_temp_path = function(prefix, parent) {
    paths[[if (prefix == "easynis-spill-") 1L else 2L]]
  })

  expect_error(suppressWarnings(nis_open(fixture)), "private DuckDB spill directory")
  target <- file.path(parent, "cohort")
  expect_error(suppressWarnings(nis_write_cohort(query, TRUE, target, AGE)), "temporary sibling")
  expect_false(file.exists(target))
  for (path in paths) {
    expect_true(file.exists(file.path(path, "sentinel")))
  }
})
