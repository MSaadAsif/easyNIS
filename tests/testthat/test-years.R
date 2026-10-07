test_that("the installed roadmap distinguishes targets from supported years", {
  roadmap <- nis_supported_years()
  expect_identical(roadmap$year, 1988:2023)
  expect_true(all(roadmap$status == "target"))
  expect_true(all(roadmap$metadata_audit == "pending"))
  for (capability in c("import", "cohorts", "survey", "models", "tables")) {
    expect_true(all(roadmap[[capability]] == "not_implemented"))
  }
  expect_equal(nrow(nis_supported_years(supported_only = TRUE)), 0L)
  expect_identical(names(nis_supported_years(supported_only = TRUE)), names(roadmap))
})

test_that("year requests select without inventing or duplicating support", {
  selected <- nis_supported_years(c(2022, 2017, 2022))
  expect_identical(selected$year, c(2017L, 2022L))
  expect_true(all(selected$target_stage == "v1"))
  expect_equal(nrow(nis_supported_years(numeric())), 0L)
  expect_error(nis_supported_years(2024), "outside the roadmap")
  for (years in list("2022", NA_real_, Inf, 2022.5, TRUE, 2022 + 1i,
                    as.Date("2022-01-01"))) {
    expect_error(nis_supported_years(years), "whole numeric years")
  }
  for (flag in list(NA, 1, "TRUE", c(TRUE, FALSE), logical())) {
    expect_error(nis_supported_years(supported_only = flag), "TRUE or FALSE")
  }
})
