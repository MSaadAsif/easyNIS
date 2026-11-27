lazy_glm_fixture <- function() {
  query <- suppressWarnings(nis_open(nis_example(2018:2020)))
  dplyr::mutate(
    query,
    female_flag = FEMALE == 1L,
    response = ifelse(HOSP_NIS == 2L & YEAR == 2018, NA_real_, (AGE + TOTCHG) %% 3L == 0L),
    los_days = ifelse(HOSP_NIS == 3L & YEAR == 2019, NA_real_, LOS),
    shifted_y = 1e12 + 4000 * los_days,
    shifted_x = 1e12 + AGE,
    not_in_domain = ifelse(YEAR == 2018L, dbplyr::sql("CAST(1e999 AS DOUBLE)"), AGE),
    alternate = DISCWT * (1 + FEMALE / 4)
  )
}

expect_lazy_glm <- function(fit, ref) {
  expect_lazy_stat(fit, ref)
  expect_equal(fit$df.residual, ref$df.residual)
  expect_equal(unname(as.numeric(survey::SE(fit))), unname(as.numeric(survey::SE(ref))), tolerance = 1e-8)
}

test_that("lazy GLMs agree with independent survey fits on nested domains", {
  withr::local_options(list(
    survey.lonely.psu = "fail",
    survey.adjust.domain.lonely = FALSE,
    easyNIS.duckdb_config = list(threads = 2L)
  ))
  query <- lazy_glm_fixture()
  ref <- lazy_reference(dplyr::mutate(query, DISCWT = alternate))
  design <- nis_survey(query, weights = alternate)
  domain <- subset(design, YEAR > 2018 & HOSP_NIS %% 4L != 0L)
  subref <- subset(ref, YEAR > 2018 & HOSP_NIS %% 4L != 0L)
  for (family in list(stats::gaussian(), stats::poisson(), stats::quasipoisson())) {
    expect_lazy_glm(
      survey::svyglm(los_days ~ not_in_domain + female_flag + factor(YEAR), domain, family = family),
      survey::svyglm(los_days ~ not_in_domain + female_flag + factor(YEAR), subref, family = family)
    )
  }
  formula <- response ~ AGE + female_flag + factor(YEAR)
  for (family in list(stats::binomial(), stats::quasibinomial())) {
    expect_lazy_glm(
      suppressWarnings(survey::svyglm(formula, design, family = family)),
      suppressWarnings(survey::svyglm(formula, ref, family = family))
    )
  }
  fit <- survey::svyglm(formula, design, family = stats::quasibinomial())
  expect_output(print(fit), "Coefficients")
  if (requireNamespace("broom", quietly = TRUE)) {
    expected <- broom::tidy(survey::svyglm(formula, ref, family = stats::quasibinomial()), conf.int = TRUE)
    expect_equal(broom::tidy(fit, conf.int = TRUE), expected, tolerance = 1e-8)
  }
  if (requireNamespace("gtsummary", quietly = TRUE)) {
    tab <- gtsummary::tbl_regression(fit, exponentiate = TRUE)
    expect_s3_class(tab, "tbl_regression")
    expect_equal(tab$N, stats::nobs(fit))
    expect_equal(sum(is.finite(tab$table_body$estimate)), length(stats::coef(fit)) - 1L)
  }
})

test_that("lazy GLMs back-transform and reject numerically aliased Gram systems", {
  withr::local_options(list(
    survey.lonely.psu = "fail",
    survey.adjust.domain.lonely = FALSE,
    easyNIS.duckdb_config = list(threads = 2L)
  ))
  query <- lazy_glm_fixture()
  reference <- lazy_reference(query)
  ref <- survey::svyglm(los_days ~ AGE + female_flag, reference)
  design <- nis_survey(query)
  shifted <- survey::svyglm(shifted_y ~ shifted_x + female_flag, design)
  transform <- diag(rep(4000, 3L))
  transform[1, 2] <- -4000 * 1e12
  offset <- c(1e12, 0, 0)
  expect_equal(unname(stats::coef(shifted)), drop(transform %*% stats::coef(ref)) + offset, tolerance = 1e-8)
  expect_equal(unname(stats::vcov(shifted)), transform %*% stats::vcov(ref) %*% t(transform), tolerance = 1e-8)

  records <- dplyr::collect(query)
  records$noise <- withr::with_seed(2601, stats::rnorm(nrow(records)))
  path <- withr::local_tempdir()
  for (year in sort(unique(records$YEAR))) {
    write_duckdb_parquet(
      records[records$YEAR == year, ],
      file.path(path, sprintf("NIS_%d.parquet", year))
    )
  }
  rank_fixture <- nis_open(path, check_release = FALSE)
  formula <- los_days ~ AGE + FEMALE + X_NEAR
  for (delta in c(0, 10^seq.int(-10L, -5L))) {
    tilted <- dplyr::mutate(rank_fixture, X_NEAR = AGE + 0.3 * FEMALE + !!delta * noise)
    qr_fit <- survey::svyglm(formula, lazy_reference(tilted))
    if (delta <= 1e-10) {
      expect_true(is.na(stats::coef(qr_fit, na.rm = FALSE)[["X_NEAR"]]))
    }
    if (delta == 1e-5) {
      expect_true(is.finite(stats::coef(qr_fit)[["X_NEAR"]]))
    }
    expect_error(survey::svyglm(formula, nis_survey(tilted)), "[Rr]ank deficient|[Ii]ll-conditioned")
  }
  well_conditioned <- dplyr::mutate(query, x = AGE / 100, alias_x = x + TOTCHG / 1e5)
  expect_lazy_glm(
    survey::svyglm(los_days ~ x + alias_x, nis_survey(well_conditioned)),
    survey::svyglm(los_days ~ x + alias_x, lazy_reference(well_conditioned))
  )
  separated <- nis_survey(dplyr::mutate(query, dies = AGE > 50))
  expect_error(survey::svyglm(dies ~ AGE, separated, family = stats::quasibinomial()), "separation")
  expect_error(survey::svyglm(los_days ~ AGE, design, family = stats::Gamma()), "nis_design")
  expect_error(
    survey::svyglm(response ~ AGE, design, family = stats::quasibinomial(), control = stats::glm.control(maxit = 1L)),
    "converge"
  )
})

test_that("wide whole-sample fits agree on the six-year invented fixture", {
  skip_if_not(tolower(Sys.getenv("EASYNIS_FULL_TESTS")) %in% c("true", "1"))
  withr::local_options(list(
    survey.lonely.psu = "fail",
    survey.adjust.domain.lonely = FALSE,
    easyNIS.duckdb_config = list(threads = 2L)
  ))
  query <- suppressWarnings(nis_open(nis_example(2017:2022)))
  extra <- lapply(seq_len(20L), function(i) {
    dbplyr::sql(sprintf("(hash(AGE, LOS, YEAR, HOSP_NIS, %d) %% 11) < 3", i))
  })
  names(extra) <- paste0("flag", seq_along(extra))
  query <- dplyr::mutate(query, !!!extra)
  reference <- lazy_reference(query)
  design <- nis_survey(query)
  model <- stats::reformulate(c("AGE", "FEMALE", "factor(YEAR)", names(extra)), "LOS")
  expect_lazy_glm(survey::svyglm(model, design), survey::svyglm(model, reference))
})

test_that("lazy GLMs preserve ENUM levels and name non-treatment contrasts", {
  withr::local_options(list(
    survey.lonely.psu = "fail",
    easyNIS.duckdb_config = list(threads = 2L),
    contrasts = c("contr.treatment", "contr.poly")
  ))
  query <- lazy_glm_fixture() |>
    dplyr::mutate(
      severity = dbplyr::sql(
        "CAST(CASE WHEN AGE < 40 THEN 'Low' WHEN AGE < 70 THEN 'Medium'
        ELSE 'High' END AS ENUM('Low', 'Medium', 'High'))"
      ),
      event = dbplyr::sql(
        "CAST(CASE WHEN response = 1 THEN 'Yes' WHEN response = 0 THEN 'No'
        END AS ENUM('Yes', 'No'))"
      )
    )
  design <- nis_survey(query)
  reference <- lazy_reference(query)
  expect_identical(levels(reference$variables$severity), c("Low", "Medium", "High"))
  expect_identical(levels(reference$variables$event), c("Yes", "No"))
  logistic <- stats::quasibinomial()
  expect_lazy_glm(
    survey::svyglm(event ~ AGE + severity, design, family = logistic),
    survey::svyglm(event ~ AGE + severity, reference, family = logistic)
  )
  for (contrast in c("contr.sum", "contr.helmert")) {
    withr::with_options(list(contrasts = c(contrast, "contr.poly")), {
      expect_lazy_glm(
        survey::svyglm(los_days ~ AGE + severity, design),
        survey::svyglm(los_days ~ AGE + severity, reference)
      )
    })
  }
  expect_identical(
    survey::degf(subset(design, HOSP_NIS < 6L)),
    survey::degf(subset(reference, HOSP_NIS < 6L))
  )
})
