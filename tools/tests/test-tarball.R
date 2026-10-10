test_that("tarball gate permits only the expected generated vignette index", {
  script <- normalizePath(file.path("..", "check-tarball.R"), winslash = "/")
  root <- tempfile("invented-tarball-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  previous <- setwd(root)
  on.exit(setwd(previous), add = TRUE, after = FALSE)
  files <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R/years.R", "R/synthetic.R",
    "man/nis_supported_years.Rd", "man/nis_synthetic_data.Rd",
    "inst/metadata/year-support.csv", "inst/CITATION",
    "vignettes/synthetic-workflow.Rhtml", "inst/doc/synthetic-workflow.Rhtml",
    "inst/doc/synthetic-workflow.R", "inst/doc/synthetic-workflow.html")
  for (file in files) {
    path <- file.path("easyNIS", file)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("Invented test placeholder", path)
  }
  dir.create("easyNIS/build")
  index <- data.frame(File = "synthetic-workflow.Rhtml",
    Title = "Offline synthetic import-to-export workflow",
    PDF = "synthetic-workflow.html", R = "synthetic-workflow.R",
    stringsAsFactors = FALSE)
  index$Depends <- list(Depends = character())
  index$Keywords <- list(Keywords = character())
  saveRDS(index, "easyNIS/build/vignette.rds")
  check <- function() {
    utils::tar("fixture.tar.gz", files = "easyNIS", compression = "gzip", tar = "internal")
    environment <- new.env(parent = globalenv())
    environment$commandArgs <- function(...) "fixture.tar.gz"
    capture.output(sys.source(script, envir = environment))
  }
  expect_match(check(), "Tarball inspection passed")
  saveRDS(data.frame(invented_record = 1), "easyNIS/build/vignette.rds")
  expect_error(check(), "Unexpected vignette index metadata")
  index$Title <- "C:/private/invented-source"
  saveRDS(index, "easyNIS/build/vignette.rds")
  expect_error(check(), "Unexpected vignette index metadata")
  index$Title <- "Offline synthetic import-to-export workflow"
  saveRDS(index, "easyNIS/build/vignette.rds")
  saveRDS(data.frame(invented_record = 1), "easyNIS/inst/records.rds")
  expect_error(check(), "Forbidden tarball entries.*inst/records.rds")
  unlink("easyNIS/inst/records.rds")
  unlink("easyNIS/inst/doc/synthetic-workflow.html")
  expect_error(check(), "Missing vignette entries")
})
