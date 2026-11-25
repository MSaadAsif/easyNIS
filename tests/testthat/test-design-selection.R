selection_fixture <- function() {
  dplyr::tibble(
    YEAR = 2020L, HOSP_NIS = rep(1:3, each = 2), NIS_STRATUM = 1L,
    DISCWT = c(1, 2, 3, 4, 5, 6), AGE = c(40, 60, 20, 30, 50, 70),
    LOS = c(2, 8, 1, 3, 4, 6), eligible = c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE),
    text = letters[1:6], TOTCHG = seq(100, 600, 100), CCR_NIS = 0.25
  )
}

test_that("keep aliases select source values and preserve source labels on both backends", {
  data <- selection_fixture()
  expected <- nis_design(data, eligible, keep = LOS)
  reference <- survey::svymean(~LOS, expected)
  for (input in list(data, duckdb_query_fixture(data))) {
    design <- nis_design(input, eligible, keep = c(AGE = LOS))
    expect_equal(as.numeric(design$variables$AGE), data$LOS[data$eligible])
    expect_false("LOS" %in% names(design$variables))
    expect_identical(attr(design$variables$AGE, "label"),
      attr(expected$variables$LOS, "label"))
    estimate <- survey::svymean(~AGE, design)
    expect_equal(unname(coef(estimate)), unname(coef(reference)))
    expect_equal(unname(survey::SE(estimate)), unname(survey::SE(reference)))
    expect_equal(unname(coef(estimate)), weighted.mean(data$LOS[data$eligible],
      data$DISCWT[data$eligible]))

    aliases <- c(stay = "LOS", years_old = "AGE")
    from_vector <- nis_design(input, eligible, keep = aliases)
    from_helper <- nis_design(input, eligible, keep = tidyselect::all_of(aliases))
    expect_equal(from_vector$variables, from_helper$variables)
    expect_equal(as.numeric(from_vector$variables$stay), data$LOS[data$eligible])
    swap <- nis_design(input, eligible, keep = c(LOS = AGE, AGE = LOS))
    expect_equal(as.numeric(swap$variables$LOS), data$AGE[data$eligible])
    expect_equal(as.numeric(swap$variables$AGE), data$LOS[data$eligible])
    copies <- nis_design(input, eligible, keep = c(first = LOS, second = LOS))
    expect_equal(copies$variables$first, copies$variables$second)
  }
})

test_that("keep predicates use real local and lazy computed column types", {
  data <- selection_fixture()
  for (input in list(data, duckdb_query_fixture(data))) {
    input <- dplyr::mutate(input, computed_flag = AGE > 45, payload = paste0(text, text))
    logical_design <- nis_design(input, TRUE, keep = tidyselect::where(is.logical))
    expect_true(all(c("eligible", "computed_flag") %in% names(logical_design$variables)))
    expect_false(any(c("AGE", "text", "payload") %in% names(logical_design$variables)))
    expect_equal(unname(coef(survey::svymean(~eligible, logical_design))),
      c(weighted.mean(!data$eligible, data$DISCWT), weighted.mean(data$eligible, data$DISCWT)))
    numeric_design <- nis_design(input, TRUE, keep = tidyselect::where(is.numeric))
    expect_true(all(c("AGE", "LOS", "TOTCHG", "CCR_NIS") %in% names(numeric_design$variables)))
    expect_false(any(c("text", "payload", "eligible", "computed_flag") %in% names(numeric_design$variables)))
    expect_equal(unname(coef(survey::svymean(~LOS, numeric_design))),
      weighted.mean(data$LOS, data$DISCWT))
    character_design <- nis_design(input, TRUE, keep = tidyselect::where(is.character))
    expect_true(all(c("text", "payload") %in% names(character_design$variables)))
    expect_false("AGE" %in% names(character_design$variables))
    empty <- nis_design(input, TRUE, keep = tidyselect::any_of("absent"))
    expect_true(all(c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT") %in% names(empty$variables)))
    expect_false("LOS" %in% names(empty$variables))
  }
})

test_that("aliases preserve required design and cost fields and reject collisions", {
  data <- selection_fixture()
  for (input in list(data, duckdb_query_fixture(data))) {
    design <- nis_design(input, eligible,
      keep = c(year_copy = YEAR, bill = TOTCHG, ratio = CCR_NIS), dollars = 2022)
    reference <- nis_design(data, eligible, keep = c(TOTCHG, CCR_NIS), dollars = 2022)
    expect_equal(design$variables$YEAR, design$variables$year_copy)
    expect_equal(design$variables$TOTCHG, design$variables$bill)
    expect_equal(design$variables$CCR_NIS, design$variables$ratio)
    expect_equal(design$variables$cost_adj, reference$variables$cost_adj)
    expect_identical(nis_cost_provenance(design), nis_cost_provenance(reference))
    expect_equal(as.numeric(stats::weights(design)), data$DISCWT[data$eligible])
    expect_error(nis_design(input, TRUE, keep = c(YEAR = LOS)), "retained field")
    expect_error(nis_design(input, TRUE,
      keep = c(TOTCHG, CCR_NIS, cost_adj = LOS)), "retained field")
    expect_error(nis_design(input, TRUE,
      keep = c(TOTCHG = LOS, bill = TOTCHG, CCR_NIS)), "retained field")
    expect_error(nis_design(input, TRUE, keep = c(.hidden = LOS)), "dot-prefixed")
  }
})

test_that("lazy type selection does not materialize unselected row expressions", {
  data <- selection_fixture()
  query <- duckdb_query_fixture(data) |>
    dplyr::mutate(unselected_payload = dbplyr::sql(
      "CAST(error('unselected payload must not be evaluated') AS VARCHAR)"
    ))
  design <- nis_design(query, eligible, keep = tidyselect::where(is.numeric))
  expect_false("unselected_payload" %in% names(design$variables))
  expect_equal(unname(coef(survey::svymean(~LOS, design))),
    weighted.mean(data$LOS[data$eligible], data$DISCWT[data$eligible]))
})

test_that("aliases preserve adjusted-cost sources before costs are recomputed", {
  data <- selection_fixture()
  data$cost_adj <- 901:906
  data$charges_adj <- 801:806
  reference <- nis_design(data, eligible, keep = c(TOTCHG, CCR_NIS), dollars = 2022)
  for (input in list(data, duckdb_query_fixture(data))) {
    design <- nis_design(input, eligible,
      keep = c(TOTCHG, CCR_NIS, cost_adj, charges_adj,
        original_cost = cost_adj, original_charge = charges_adj), dollars = 2022)
    expect_equal(as.numeric(design$variables$original_cost), data$cost_adj[data$eligible])
    expect_equal(as.numeric(design$variables$original_charge), data$charges_adj[data$eligible])
    expect_equal(design$variables$cost_adj, reference$variables$cost_adj)
    expect_equal(design$variables$charges_adj, reference$variables$charges_adj)
    expect_identical(attr(design$variables$original_cost, "label"),
      attr(nis_label(data)$cost_adj, "label"))
    expect_identical(nis_cost_provenance(design), nis_cost_provenance(reference))
  }
})


test_that("DuckDB input cannot shadow a reserved design field by case", {
  frame <- dplyr::tibble(YEAR = 2020L, HOSP_NIS = 1L, NIS_STRATUM = 1L,
    DISCWT = 1, .NIS_COHORT = TRUE)
  expect_error(nis_design(duckdb_query_fixture(frame), .NIS_COHORT, keep = YEAR),
    "internal design names are reserved")
})
