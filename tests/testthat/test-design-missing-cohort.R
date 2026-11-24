missing_cohort_fixture <- function() {
  dplyr::tibble(
    YEAR = 2020L, HOSP_NIS = rep(1:4, each = 2L),
    NIS_STRATUM = rep(1:2, each = 4L), DISCWT = 2,
    AGE = seq(30, 65, by = 5),
    missing = NA, eligible = c(TRUE, NA, FALSE, NA, TRUE, FALSE, NA, TRUE)
  )
}

test_that("injected SQL cohorts are validated by their bound type", {
  frame <- missing_cohort_fixture()
  query <- duckdb_query_fixture(frame)
  predicate <- dbplyr::sql("AGE > 45")
  design <- nis_design(query, !!predicate, keep = AGE)
  reference <- nis_design(frame, AGE > 45, keep = AGE)
  expect_equal(design$variables, reference$variables)
  expect_equal(unname(coef(survey::svymean(~AGE, design))),
    unname(coef(survey::svymean(~AGE, reference))))
  for (invalid in list(dbplyr::sql("AGE"), dbplyr::sql("'invalid'"))) {
    expect_error(nis_design(query, !!invalid, keep = AGE), "logical vector")
  }
})

test_that("untyped and typed missing logical cohorts agree across backends", {
  frame <- missing_cohort_fixture()
  query <- duckdb_query_fixture(frame)
  expressions <- rlang::exprs(NA, missing, NA & TRUE)
  for (data in list(frame, query, dplyr::mutate(query, missing = NA))) {
    for (cohort in expressions) {
      expect_message(
        expect_warning(
          design <- nis_design(data, !!cohort, keep = AGE),
          "No cohort discharges in year 2020"
        ),
        "Treated 8 missing cohort values as outside the cohort"
      )
      expect_equal(nrow(design$variables), 0L)
      expect_identical(attr(design, "nis_cohort_rows"), 0L)
      expect_equal(nrow(attr(design, "nis_placeholder_rows")), 4L)
      expect_equal(unname(coef(survey::svytotal(~AGE, design))), 0)
    }
  }
})

test_that("empty cohorts and empty sources preserve backend parity", {
  frame <- missing_cohort_fixture()
  query <- duckdb_query_fixture(frame)
  for (data in list(frame, query)) {
    expect_warning(design <- nis_design(data, FALSE, keep = AGE),
      "No cohort discharges in year 2020")
    expect_equal(nrow(design$variables), 0L)
    expect_equal(nrow(attr(design, "nis_placeholder_rows")), 4L)
    empty <- dplyr::filter(data, FALSE)
    expect_error(suppressWarnings(nis_design(empty, NA, keep = AGE)),
      "No discharges have valid design fields")
  }
})

test_that("missing cohorts count only discharges with valid design fields", {
  frame <- missing_cohort_fixture()
  frame$DISCWT[1L] <- NA_real_
  for (data in list(frame, duckdb_query_fixture(frame))) {
    expect_message(
      design <- suppressWarnings(nis_design(data, NA, keep = AGE)),
      "Treated 7 missing cohort values as outside the cohort"
    )
    expect_equal(attr(design, "nis_excluded")$total, 1)
    expect_equal(nrow(design$variables), 0L)
  }
})

test_that("mixed logical missing cohorts retain survey estimates and variance", {
  frame <- missing_cohort_fixture()
  query <- duckdb_query_fixture(frame)
  expect_message(local <- nis_design(frame, eligible, keep = AGE),
    "Treated 3 missing cohort values")
  expect_message(lazy <- nis_design(query, eligible, keep = AGE),
    "Treated 3 missing cohort values")
  reference <- survey::svydesign(
    ids = ~HOSP_NIS, strata = ~NIS_STRATUM, weights = ~DISCWT,
    data = frame, nest = TRUE
  )
  reference <- subset(reference, !is.na(eligible) & eligible)
  for (design in list(local, lazy)) {
    expect_identical(attr(design, "nis_cohort_rows"), 3L)
    expect_equal(as.numeric(stats::weights(design)), rep(2, 3))
    for (estimate in list(survey::svytotal, survey::svymean)) {
      actual <- estimate(~AGE, design)
      expected <- estimate(~AGE, reference)
      expect_equal(coef(actual), coef(expected), tolerance = 1e-8)
      expect_equal(vcov(actual), vcov(expected), tolerance = 1e-8)
    }
  }
})

test_that("nonlogical cohorts remain invalid even when all missing", {
  frame <- missing_cohort_fixture() |>
    dplyr::mutate(
      numeric_missing = NA_real_, integer_missing = NA_integer_,
      character_missing = NA_character_, numeric_value = 1,
      character_value = "TRUE"
    )
  query <- duckdb_query_fixture(frame)
  expressions <- rlang::exprs(
    NA_real_, NA_integer_, NA_character_, 0, 1, "TRUE",
    numeric_missing, integer_missing, character_missing,
    numeric_value, character_value
  )
  for (data in list(frame, query)) {
    for (cohort in expressions) {
      expect_error(nis_design(data, !!cohort, keep = AGE),
        "`cohort` must evaluate to a logical vector", fixed = TRUE)
    }
  }
  # Mutated typed NULLs must not be mistaken for an untyped SQL NULL either.
  mutated <- dplyr::mutate(query,
    numeric_missing = as.double(NA), character_missing = as.character(NA))
  expect_error(nis_design(mutated, numeric_missing, keep = AGE), "logical vector")
  expect_error(nis_design(mutated, character_missing, keep = AGE), "logical vector")
})
