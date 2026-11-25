test_that("package citation follows the declared authors and repository", {
  description_path <- test_path("../../DESCRIPTION")
  description <- if (file.exists(description_path)) {
    as.list(read.dcf(description_path)[1L, ])
  } else {
    utils::packageDescription("easyNIS")
  }
  people <- eval(parse(text = description[["Authors@R"]]), envir = globalenv())
  authors <- people[vapply(people, function(person) "aut" %in% person$role, logical(1))]
  citation <- utils::readCitationFile(system.file("CITATION", package = "easyNIS"),
    meta = description)
  expect_identical(citation$title, paste0(description$Package, ": ", description$Title))
  expect_identical(format(citation$author, include = c("given", "family")),
    format(authors, include = c("given", "family")))
  orcid <- function(people) vapply(people, function(person) person$comment[["ORCID"]], character(1))
  expect_identical(orcid(citation$author), orcid(authors))
  expect_identical(citation$url, trimws(strsplit(description$URL, ",", fixed = TRUE)[[1L]][[1L]]))
})
