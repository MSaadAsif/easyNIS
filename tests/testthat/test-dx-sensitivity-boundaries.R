# All expectations below use invented discharges and hand-calculated totals.
dx_boundary_fixture <- function() {
  dplyr::tibble(
    g = c("a", "b", "a", "b", "c"), h = c(1, 1, 2, 2, 3),
    I10_DX1 = c("A100", "A100", "Z999", "Z999", NA_character_),
    I10_DX2 = c(NA, NA, "A100", "A100", NA_character_),
    DISCWT = c(2, 3, 0, NA, 7), DIED = c(1, 0, NA, 1, 0),
    DIED_weighted = c(0, 1, 1, NA, 1),
    DIED_weighted_weighted = c(1, 0, NA, 1, 0),
    .nis_dx_summary_1_n = c(0, 1, 1, NA, 1),
    .nis_dx_principal_DIED_n = c(1, 0, NA, 1, 0),
    `odd outcome` = c(0, 1, 1, NA, 1)
  )
}

test_that("Local and DuckDB sensitivity ignores all input groups", {
  for (make_input in list(identity, duckdb_query_fixture)) {
    data <- make_input(dx_boundary_fixture())
    for (groups in list(character(), "g", c("g", "h"))) {
      grouped <- dplyr::group_by(data, !!!rlang::syms(groups))
      expect_no_warning(out <- nis_dx_sensitivity(grouped, "A1"))
      expect_identical(out$presentation, c("principal", "secondary_only", "any"))
      expect_equal(out$n_unweighted, c(2, 2, 4))
      expect_equal(out$n_weighted, c(5, 0, 5))
      expect_equal(out$pct_of_any_unweighted, c(50, 50, 100))
      expect_equal(out$pct_of_any_weighted, c(100, 0, 100))
      expect_equal(out$DIED_rate_unweighted, c(1 / 2, 1, 2 / 3))
      expect_equal(out$DIED_rate_weighted, c(2 / 5, NA, 2 / 5))
      expect_false(dplyr::is_grouped_df(out))
      expect_equal(dplyr::group_vars(grouped), groups)
    }
  }
})

test_that("Local and DuckDB empty and unmatched summaries have zero totals", {
  for (make_input in list(identity, duckdb_query_fixture)) {
    data <- make_input(dx_boundary_fixture())
    for (groups in list(character(), "g", c("g", "h"))) {
      grouped <- dplyr::group_by(data, !!!rlang::syms(groups))
      for (input in list(dplyr::filter(grouped, FALSE), grouped)) {
        out <- nis_dx_sensitivity(input, "B2")
        expect_equal(out$n_unweighted, c(0, 0, 0))
        expect_equal(out$n_weighted, c(0, 0, 0))
        expect_true(all(is.na(out$pct_of_any_unweighted)))
        expect_true(all(is.na(out$pct_of_any_weighted)))
        expect_true(all(is.na(out$DIED_rate_unweighted)))
        expect_true(all(is.na(out$DIED_rate_weighted)))
      }
    }
    out <- nis_dx_sensitivity(dplyr::filter(data, FALSE), "A1", outcomes = character())
    expect_named(out, c("presentation", "n_unweighted", "n_weighted",
      "pct_of_any_unweighted", "pct_of_any_weighted"))
  }
})

test_that("Local and DuckDB outcome rates are independent of names and order", {
  for (make_input in list(identity, duckdb_query_fixture)) {
    fixture <- dx_boundary_fixture()
    data <- make_input(fixture)
    outcomes <- c("DIED", "DIED_weighted", "DIED_weighted_weighted",
      ".nis_dx_summary_1_n", ".nis_dx_principal_DIED_n", "odd outcome")
    for (order in list(outcomes, rev(outcomes))) {
      out <- nis_dx_sensitivity(data, "A1", outcomes = order)
      expect_named(out, c("presentation", "n_unweighted", "n_weighted",
        "pct_of_any_unweighted", "pct_of_any_weighted",
        as.vector(rbind(paste0(order, "_rate_unweighted"), paste0(order, "_rate_weighted")))))
      for (outcome in outcomes) {
        first <- fixture[[outcome]][[1L]] == 1
        expected <- if (first) c(2 / 5, NA, 2 / 5) else c(3 / 5, NA, 3 / 5)
        unweighted <- c(1 / 2, 1, 2 / 3)
        alone <- nis_dx_sensitivity(data, "A1", outcomes = outcome)
        expect_equal(out[[paste0(outcome, "_rate_weighted")]], expected)
        expect_equal(out[[paste0(outcome, "_rate_unweighted")]], unweighted)
        expect_equal(out[names(alone)], alone)
      }
    }
  }
})

test_that("Local and DuckDB zero and missing weights keep omission arithmetic", {
  for (make_input in list(identity, duckdb_query_fixture)) {
    for (weights in list(rep(0, 5), rep(NA_real_, 5))) {
      fixture <- dx_boundary_fixture()
      fixture$DISCWT <- weights
      out <- nis_dx_sensitivity(make_input(fixture), "A1")
      expect_equal(out$n_unweighted, c(2, 2, 4))
      expect_equal(out$n_weighted, c(0, 0, 0))
      expect_equal(out$DIED_rate_unweighted, c(1 / 2, 1, 2 / 3))
      expect_true(all(is.na(out$DIED_rate_weighted)))
      expect_true(all(is.na(out$pct_of_any_weighted)))
    }
    fixture <- dx_boundary_fixture()
    fixture$DIED <- NA_real_
    out <- nis_dx_sensitivity(make_input(fixture), "A1")
    expect_equal(out$n_weighted, c(5, 0, 5))
    expect_true(all(is.na(out$DIED_rate_unweighted)))
    expect_true(all(is.na(out$DIED_rate_weighted)))
  }
})

test_that("Local and DuckDB available slots and eligibility still govern flags", {
  for (make_input in list(identity, duckdb_query_fixture)) {
    fixture <- dx_boundary_fixture()
    fixture$YEAR <- 2019L
    fixture$DXVER <- c(10L, 9L, 10L, 10L, 10L)
    data <- make_input(fixture)
    out <- nis_dx_sensitivity(data, "A1")
    expect_equal(out$n_unweighted, c(1, 2, 3))
    capped <- nis_dx_sensitivity(dplyr::select(data, -I10_DX2), "A1")
    expect_equal(capped$n_unweighted, c(1, 0, 1))
  }
})

test_that("sensitivity does not alter input metadata", {
  data <- dx_boundary_fixture()
  attr(data, "synthetic_metadata") <- list(source = "invented", slots = 2L)
  before <- data
  invisible(nis_dx_sensitivity(data, "A1"))
  expect_identical(data, before)
})


test_that("sensitivity does not overwrite or reject analyst fields named like flags", {
  data <- dplyr::tibble(YEAR = 2020L, I10_DX1 = c("I50", "Z99"),
    DISCWT = c(2, 5), .NIS_DX_ANY = c(1, 0))
  for (input in list(data, duckdb_query_fixture(data))) {
    result <- nis_dx_sensitivity(input, "I50", outcomes = ".NIS_DX_ANY")
    expect_identical(result$n_unweighted, c(1, 0, 1))
    expect_equal(result[[".NIS_DX_ANY_rate_unweighted"]], c(1, NA, 1))
  }
})
