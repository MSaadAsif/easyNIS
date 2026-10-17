test_that("design validation rejects ambiguous or incomplete inputs", {
  path <- nis_example(2019)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  data <- dplyr::collect(nis_open(path))
  expect_error(nis_design(data, TRUE, AGE, annualize = NA), "annualize")
  expect_error(nis_design(data["AGE"], TRUE, AGE), "missing design")
  data$.nis_weight <- 1
  expect_error(nis_design(data, TRUE, AGE), "reserved")
  data$.nis_weight <- NULL
  data$.analysis <- 1
  expect_error(nis_design(data, TRUE, .analysis), "dot-prefixed")
  expect_error(nis_design(data, TRUE, AGE, dollars = 2024), "Keep both")
  data$NIS_STRATUM[[1L]] <- 2L
  expect_error(nis_design(data, TRUE, AGE), "one stratum")
})

test_that("reweighting rejects a design narrowed after cohort definition", {
  path <- nis_example(2019)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  design <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50") |>
    nis_design(heart_failure, keep = AGE)
  narrowed <- dplyr::filter(design, AGE > min(AGE))
  expect_error(nis_reweight(narrowed, rep(1, nrow(narrowed$variables))),
    "has been narrowed")
})

test_that("nis_design placeholder designs match full-data domain estimates", {
  designs <- comparison_designs()
  on.exit(unlink(designs$path, recursive = TRUE), add = TRUE)

  old_lonely <- getOption("survey.lonely.psu")
  old_adjust <- getOption("survey.adjust.domain.lonely")
  on.exit(options(
    survey.lonely.psu = old_lonely,
    survey.adjust.domain.lonely = old_adjust
  ), add = TRUE)

  settings <- list(
    adjusted = list(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE),
    default = list(survey.lonely.psu = NULL, survey.adjust.domain.lonely = NULL)
  )

  for (setting in settings) {
    do.call(options, setting)
    full <- designs$full
    placeholder <- designs$placeholder

    mean_full <- survey::svymean(~AGE + LOS, full)
    mean_placeholder <- survey::svymean(~AGE + LOS, placeholder)
    expect_equal(coef(mean_placeholder), coef(mean_full), tolerance = 1e-8)
    expect_equal(survey::SE(mean_placeholder), survey::SE(mean_full), tolerance = 1e-8)

    total_full <- survey::svytotal(~AGE + LOS, full)
    total_placeholder <- survey::svytotal(~AGE + LOS, placeholder)
    expect_equal(coef(total_placeholder), coef(total_full), tolerance = 1e-8)
    expect_equal(survey::SE(total_placeholder), survey::SE(total_full), tolerance = 1e-8)

    by_full <- survey::svyby(~AGE, ~FEMALE, full, survey::svymean, vartype = "se")
    by_placeholder <- survey::svyby(
      ~AGE, ~FEMALE, placeholder, survey::svymean, vartype = "se"
    )
    expect_equal(coef(by_placeholder), coef(by_full), tolerance = 1e-8)
    expect_equal(survey::SE(by_placeholder), survey::SE(by_full), tolerance = 1e-8)

    logistic_full <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = full,
      family = stats::quasibinomial()
    )
    logistic_placeholder <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = placeholder,
      family = stats::quasibinomial()
    )
    expect_equal(coef(logistic_placeholder), coef(logistic_full), tolerance = 1e-8)
    expect_equal(vcov(logistic_placeholder), vcov(logistic_full), tolerance = 1e-8)

    gaussian_full <- survey::svyglm(
      AGE ~ LOS + DIED + factor(YEAR), design = full, family = stats::gaussian()
    )
    gaussian_placeholder <- survey::svyglm(
      AGE ~ LOS + DIED + factor(YEAR),
      design = placeholder,
      family = stats::gaussian()
    )
    expect_equal(coef(gaussian_placeholder), coef(gaussian_full), tolerance = 1e-8)
    expect_equal(vcov(gaussian_placeholder), vcov(gaussian_full), tolerance = 1e-8)

    quantile_full <- survey::svyquantile(~AGE, full, quantiles = 0.5, ci = FALSE)
    quantile_placeholder <- survey::svyquantile(
      ~AGE, placeholder, quantiles = 0.5, ci = FALSE
    )
    expect_equal(coef(quantile_placeholder), coef(quantile_full), tolerance = 1e-8)
    expect_equal(survey::degf(placeholder), survey::degf(full))

    table_full <- gtsummary::tbl_svysummary(
      full,
      by = FEMALE,
      include = c(AGE, LOS),
      statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
    ) |>
      gtsummary::add_p()
    table_placeholder <- gtsummary::tbl_svysummary(
      placeholder,
      by = FEMALE,
      include = c(AGE, LOS),
      statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
    ) |>
      gtsummary::add_p()
    expect_equal(
      table_placeholder$table_body$p.value,
      table_full$table_body$p.value,
      tolerance = 1e-8
    )
  }
})

test_that("annualized weights divide by the number of years and missing cohorts are excluded", {
  path <- nis_example(2017:2019)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  annualized <- nis_design(
    query,
    heart_failure,
    keep = c(AGE),
    annualize = TRUE
  )
  expected_weights <- query |>
    dplyr::filter(heart_failure) |>
    dplyr::select(DISCWT) |>
    dplyr::collect() |>
    dplyr::pull(DISCWT) / 3
  expect_equal(as.numeric(stats::weights(annualized)), expected_weights)

  data <- dplyr::tibble(
    YEAR = c(2017, 2017), HOSP_NIS = 1:2, NIS_STRATUM = c(1, 1),
    DISCWT = c(1, 1), AGE = c(50, 60), eligible = c(TRUE, NA)
  )
  expect_message(
    domain <- nis_design(data, eligible, keep = c(AGE)),
    "1 missing cohort value"
  )
  expect_equal(nrow(domain$variables), 1L)
})

test_that("placeholder rows keep design fields and tolerate all-NA analysis values", {
  data <- dplyr::tibble(
    YEAR = c(2017, 2017),
    HOSP_NIS = c(1, 2),
    NIS_STRATUM = c(1, 1),
    DISCWT = c(1, 1),
    eligible = c(TRUE, FALSE),
    DIED = c(1, NA_real_),
    TOTCHG = c(1000, NA_real_),
    CCR_NIS = c(0.25, NA_real_)
  )

  design <- nis_design(
    data,
    eligible,
    keep = c(DIED, TOTCHG, CCR_NIS),
    dollars = 2022
  )

  expect_equal(nrow(design$variables), 1L)
  expect_identical(as.character(design$variables$DIED), "Yes")
  expect_true(is.finite(design$variables$cost_adj[[1L]]))
  expect_equal(as.numeric(design$variables$YEAR), 2017)
  expect_equal(as.numeric(design$variables$HOSP_NIS), 1)
  expect_equal(as.numeric(design$variables$NIS_STRATUM), 1)
  expect_equal(as.numeric(design$variables$DISCWT), 1)

  placeholder <- dplyr::tibble(
    YEAR = 2017,
    HOSP_NIS = 2,
    NIS_STRATUM = 1,
    DISCWT = 1,
    DIED = NA_real_,
    TOTCHG = NA_real_,
    CCR_NIS = NA_real_
  ) |>
    nis_label()
  adjusted_placeholder <- nis_cost(placeholder, dollars = 2022)
  expect_true(is.na(adjusted_placeholder$DIED[[1L]]))
  expect_true(is.na(adjusted_placeholder$cost_adj[[1L]]))
})

test_that("nis_design excludes discharges with invalid design fields and warns", {
  path <- nis_example(2017:2018)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  data <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal") |>
    dplyr::collect()
  invalid <- data
  invalid$DISCWT[c(1L, 5L)] <- c(-9, NA)
  invalid$NIS_STRATUM[9L] <- -9
  valid <- data[-c(1L, 5L, 9L), ]

  expected <- nis_design(valid, heart_failure, keep = c(AGE, LOS))
  expect_warning(
    from_frame <- nis_design(invalid, heart_failure, keep = c(AGE, LOS)),
    "Excluded 3 discharges"
  )

  invalid_path <- tempfile("nis-invalid-")
  dir.create(invalid_path)
  on.exit(unlink(invalid_path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(invalid, file.path(invalid_path, "part-0.parquet"))
  expect_warning(
    from_arrow <- nis_design(
      arrow::open_dataset(invalid_path), heart_failure, keep = c(AGE, LOS)
    ),
    "Excluded 3 discharges"
  )

  for (design in list(from_frame, from_arrow)) {
    expect_equal(nrow(design$variables), nrow(expected$variables))
    expect_equal(sort(as.numeric(stats::weights(design))),
      sort(as.numeric(stats::weights(expected))))
    expect_equal(
      survey::svymean(~AGE, design) |> coef(),
      survey::svymean(~AGE, expected) |> coef()
    )
    expect_equal(
      survey::SE(survey::svymean(~AGE, design)),
      survey::SE(survey::svymean(~AGE, expected))
    )
  }

  none <- data
  none$DISCWT <- -9
  expect_error(
    suppressWarnings(nis_design(none, heart_failure, keep = c(AGE))),
    "No discharges have valid design fields"
  )
})

test_that("multi-prefix any-position cohorts give identical designs on Arrow and data frames", {
  path <- nis_example(2017:2018)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path)
  frame <- dplyr::collect(query)
  add_flags <- function(.data) {
    nis_flag_dx(.data, exposed = c("Z515", "E11", "J18"), position = "any")
  }

  from_arrow <- nis_design(add_flags(query), exposed & AGE >= 30, keep = c(AGE, DIED))
  from_frame <- nis_design(add_flags(frame), exposed & AGE >= 30, keep = c(AGE, DIED))

  expect_equal(nrow(from_arrow$variables), nrow(from_frame$variables))
  expect_gt(nrow(from_arrow$variables), 0L)
  expect_equal(sort(as.numeric(stats::weights(from_arrow))),
    sort(as.numeric(stats::weights(from_frame))))
})

test_that("nis_reweight matches a full-data reference and keeps placeholder weights", {
  designs <- comparison_designs()
  on.exit(unlink(designs$path, recursive = TRUE), add = TRUE)

  old_lonely <- getOption("survey.lonely.psu")
  old_adjust <- getOption("survey.adjust.domain.lonely")
  on.exit(options(
    survey.lonely.psu = old_lonely,
    survey.adjust.domain.lonely = old_adjust
  ), add = TRUE)

  design <- designs$placeholder
  multipliers <- 0.6 + (seq_len(nrow(design$variables)) %% 7) / 10
  reweighted <- nis_reweight(design, multipliers)

  reference_data <- designs$full_data
  reference_data$.nis_weight[reference_data$.in_cohort] <-
    reference_data$.nis_weight[reference_data$.in_cohort] * multipliers
  reference <- srvyr::as_survey_design(
    reference_data,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)

  settings <- list(
    adjusted = list(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE),
    default = list(survey.lonely.psu = NULL, survey.adjust.domain.lonely = NULL)
  )
  max_abs_diff <- function(x, y) max(abs(as.numeric(x) - as.numeric(y)))

  for (setting in settings) {
    do.call(options, setting)

    mean_reweighted <- survey::svymean(~AGE + LOS, reweighted)
    mean_reference <- survey::svymean(~AGE + LOS, reference)
    expect_lt(max_abs_diff(coef(mean_reweighted), coef(mean_reference)), 1e-8)
    expect_lt(max_abs_diff(survey::SE(mean_reweighted), survey::SE(mean_reference)), 1e-8)

    model_reweighted <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = reweighted,
      family = stats::quasibinomial()
    )
    model_reference <- survey::svyglm(
      I(FEMALE == "Female") ~ AGE + LOS + factor(YEAR),
      design = reference,
      family = stats::quasibinomial()
    )
    expect_lt(max_abs_diff(coef(model_reweighted), coef(model_reference)), 1e-8)
    expect_lt(max_abs_diff(vcov(model_reweighted), vcov(model_reference)), 1e-8)
    expect_identical(survey::degf(reweighted), survey::degf(reference))
  }

  original_placeholders <- attr(design, "nis_placeholder_rows")
  reweighted_placeholders <- attr(reweighted, "nis_placeholder_rows")
  expect_gt(nrow(original_placeholders), 0L)
  expect_identical(
    reweighted_placeholders$.nis_weight,
    original_placeholders$.nis_weight
  )
})

test_that("nis_reweight accepts a column and validates propensity weights", {
  designs <- comparison_designs()
  on.exit(unlink(designs$path, recursive = TRUE), add = TRUE)
  data <- dplyr::collect(designs$query)
  cohort <- dplyr::coalesce(data$heart_failure, FALSE)
  data$iptw <- NA_real_
  data$iptw[cohort] <- 0.8 + (seq_len(sum(cohort)) %% 5) / 10
  design <- nis_design(data, heart_failure, keep = c(AGE, iptw))

  reweighted <- nis_reweight(design, iptw)
  expect_equal(
    as.numeric(stats::weights(reweighted)),
    as.numeric(stats::weights(design)) * data$iptw[cohort]
  )
  expect_error(nis_reweight(design, rep(1, nrow(design$variables) - 1L)),
    "one value per cohort row")
  expect_error(nis_reweight(design, rep("1", nrow(design$variables))),
    "numeric vector")
  expect_error(nis_reweight(design, c(rep(1, nrow(design$variables) - 1L), NA_real_)),
    "finite")
  expect_error(nis_reweight(design, c(rep(1, nrow(design$variables) - 1L), Inf)),
    "finite")
  expect_error(nis_reweight(design, c(rep(1, nrow(design$variables) - 1L), 0)),
    "positive")
  expect_error(nis_reweight(design, c(rep(1, nrow(design$variables) - 1L), -1)),
    "positive")
  expect_error(nis_reweight(designs$full, rep(1, nrow(designs$full$variables))),
    "must be a result of")
})

test_that("nis_design warns when the charge column is missing for a whole year", {
  data <- dplyr::tibble(
    YEAR = rep(c(2016L, 2017L), each = 2L),
    HOSP_NIS = rep(1:2, 2L), NIS_STRATUM = 1L, DISCWT = 1,
    eligible = TRUE, TOTCHG = c(1000, 1100, NA, NA), CCR_NIS = 0.25
  )
  expect_warning(
    design <- nis_design(data, eligible, keep = c(TOTCHG, CCR_NIS), dollars = 2020),
    "entirely missing in year 2017"
  )
  expect_true(all(is.na(design$variables$cost_adj[design$variables$YEAR == 2017])))

  data$TOTCHG[3L] <- 900
  expect_no_warning(
    nis_design(data, eligible, keep = c(TOTCHG, CCR_NIS), dollars = 2020)
  )
})

test_that("nis_design warns about years with hospitals but no cohort discharges", {
  data <- dplyr::tibble(
    YEAR = rep(c(2014L, 2015L, 2016L), each = 2L),
    HOSP_NIS = rep(1:2, 3L), NIS_STRATUM = 1L, DISCWT = 1,
    eligible = rep(c(FALSE, TRUE, TRUE), each = 2L)
  )
  expect_warning(
    suppressMessages(nis_design(data, eligible, keep = YEAR)),
    "No cohort discharges in year 2014"
  )
  data$eligible[1L] <- TRUE
  expect_no_warning(suppressMessages(nis_design(data, eligible, keep = YEAR)))
})

test_that("annualize divides by the distinct years, counting empty and partial years", {
  data <- dplyr::tibble(
    YEAR = rep(c(2015L, 2016L), each = 2L),
    HOSP_NIS = rep(1:2, 2L), NIS_STRATUM = 1L, DISCWT = c(4, 4, 6, 6),
    eligible = c(FALSE, FALSE, TRUE, TRUE)
  )
  design <- suppressWarnings(suppressMessages(
    nis_design(data, eligible, keep = YEAR, annualize = TRUE)
  ))
  expect_equal(design$variables$.nis_weight, c(3, 3))
})
