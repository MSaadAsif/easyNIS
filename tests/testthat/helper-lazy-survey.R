lazy_reference <- function(query) {
  records <- dplyr::collect(query)
  survey::svydesign(
    ~HOSP_NIS,
    strata = ~ interaction(YEAR, NIS_STRATUM),
    weights = ~DISCWT,
    data = records,
    nest = TRUE
  )
}

expect_lazy_stat <- function(actual, reference) {
  expect_equal(stats::coef(actual), stats::coef(reference), tolerance = 1e-8)
  expect_equal(unname(stats::vcov(actual)), unname(stats::vcov(reference)), tolerance = 1e-8)
  expect_equal(unname(stats::confint(actual)), unname(stats::confint(reference)), tolerance = 1e-8)
}
