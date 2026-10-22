test_that("package metadata identifies authors and the current license", {
  description_path <- test_path("../../DESCRIPTION")
  description <- if (file.exists(description_path)) {
    as.list(read.dcf(description_path)[1L, ])
  } else {
    utils::packageDescription("easyNIS")
  }
  authors <- eval(parse(text = description[["Authors@R"]]), envir = globalenv())

  expect_identical(description[["License"]], "AGPL-3 + file LICENSE")
  expect_identical(vapply(authors, function(author) {
    paste(author$given, author$family)
  }, character(1)), c("Muhammad Saad", "Ali Salman"))
  expect_identical(authors[[1L]]$email, "msaadasif.md@gmail.com")
  expect_identical(authors[[1L]]$comment[["ORCID"]], "0000-0002-1792-2357")
  expect_identical(authors[[2L]]$comment[["ORCID"]], "0009-0001-1102-226X")
})
