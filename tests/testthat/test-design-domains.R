test_that("srvyr filters retain the full NIS variance design", {
  query <- nis_open(shared_design_example(2019:2020)) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  expect_s3_class(query, "tbl_lazy")

  full <- dplyr::collect(query) |>
    dplyr::mutate(
      psu = interaction(YEAR, HOSP_NIS),
      stratum = interaction(YEAR, NIS_STRATUM),
      in_domain = heart_failure & NIS_STRATUM <= 2L & HOSP_NIS %% 4L != 1L,
      stay = LOS + 1
    )
  full_design <- survey::svydesign(~psu, strata = ~stratum, weights = ~DISCWT, data = full)
  reference <- subset(full_design, in_domain)
  domain_rows <- dplyr::filter(full, in_domain)
  expect_false(all(full$stratum[full$heart_failure] %in% domain_rows$stratum))
  active_strata <- dplyr::filter(full, stratum %in% domain_rows$stratum)
  expect_false(all(active_strata$psu[active_strata$heart_failure] %in% domain_rows$psu))
  expect_false(all(active_strata$psu %in% full$psu[full$heart_failure]))

  design <- nis_design(query, cohort = heart_failure, keep = c(AGE, LOS))
  expect_identical(srvyr::as_survey(design), design)
  domain <- design |>
    dplyr::filter(NIS_STRATUM <= 2L, HOSP_NIS %% 4L != 1L) |>
    dplyr::mutate(stay = LOS + 1)
  expect_lt(nrow(domain$variables), nrow(design$variables))
  expect_equal(nrow(domain$variables), nrow(domain_rows))
  expect_length(stats::weights(domain), nrow(domain_rows))

  result <- dplyr::summarise(
    domain,
    mean_stay = srvyr::survey_mean(stay),
    total_stay = srvyr::survey_total(stay),
    discharges = srvyr::unweighted(dplyr::n())
  )
  expected <- survey::svymean(~stay, reference)
  expect_equal(result$mean_stay, unname(coef(expected)), tolerance = 1e-8)
  expect_equal(result$mean_stay_se, as.numeric(survey::SE(expected)), tolerance = 1e-8)
  expect_equal(result$discharges, nrow(domain_rows))

  total <- survey::svytotal(~stay, reference)
  expect_equal(result$total_stay, as.numeric(coef(total)), tolerance = 1e-8)
  expect_equal(result$total_stay_se, as.numeric(survey::SE(total)), tolerance = 1e-8)

  # Constructing the design after filtering loses the sampled PSUs with zero
  # contributions. The fixture must distinguish that mistake from subsetting.
  restricted <- survey::svydesign(~psu, strata = ~stratum, weights = ~DISCWT, data = domain_rows)
  restricted_se <- survey::SE(survey::svymean(~stay, restricted))
  expect_gt(abs(unname(restricted_se - survey::SE(expected))), 1e-8)

  grouped <- domain |>
    dplyr::group_by(YEAR) |>
    dplyr::summarise(
      mean_stay = srvyr::survey_mean(stay),
      discharges = srvyr::unweighted(dplyr::n())
    )
  by_year <- survey::svyby(~stay, ~YEAR, reference, survey::svymean)
  expect_equal(as.integer(grouped$YEAR), by_year$YEAR)
  expect_equal(grouped$mean_stay, unname(coef(by_year)), tolerance = 1e-8)
  expect_equal(grouped$mean_stay_se, unname(survey::SE(by_year)), tolerance = 1e-8)
  expect_equal(grouped$discharges, as.integer(table(domain_rows$YEAR)))

  fit <- survey::svyglm(stay ~ AGE, design = domain)
  reference_fit <- survey::svyglm(stay ~ AGE, design = reference)
  expect_equal(coef(fit), coef(reference_fit), tolerance = 1e-8)
  expect_equal(survey::SE(fit), survey::SE(reference_fit), tolerance = 1e-8)
})

test_that("gtsummary displays only the unweighted discharges in the domain", {
  skip_if_not_installed("gtsummary")
  query <- nis_open(shared_design_example(2019:2020)) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  count <- query |>
    dplyr::filter(heart_failure, NIS_STRATUM <= 2L, HOSP_NIS %% 4L != 1L) |>
    dplyr::summarise(n = dplyr::n()) |>
    dplyr::collect()
  table <- nis_design(query, cohort = heart_failure, keep = LOS) |>
    dplyr::filter(NIS_STRATUM <= 2L, HOSP_NIS %% 4L != 1L) |>
    gtsummary::tbl_svysummary(
      include = LOS,
      type = LOS ~ "continuous",
      statistic = LOS ~ "{N_obs_unweighted}"
    )
  expect_identical(table$table_body$stat_0, as.character(count$n))
})

test_that("design reporting follows a nested domain and the fitted complete cases", {
  withr::local_options(list(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = FALSE))
  query <- nis_open(shared_design_example(2019:2020)) |>
    nis_flag_dx(heart_failure = "I50", position = "principal") |>
    dplyr::mutate(
      DISCWT = dplyr::if_else(YEAR == 2019L & HOSP_NIS == 1L & AGE == 28L, -1, DISCWT),
      NIS_STRATUM = dplyr::if_else(HOSP_NIS == 2L, 77L, NIS_STRATUM),
      predictor = dplyr::if_else(AGE %% 5L == 0L, NA_real_, as.double(AGE)),
      rare = heart_failure & (NIS_STRATUM <= 2L | NIS_STRATUM == 77L)
    )
  expect_s3_class(query, "tbl_lazy")
  full <- dplyr::collect(query)
  reference_data <- full[full$DISCWT > 0, ] |>
    dplyr::mutate(
      psu = interaction(YEAR, HOSP_NIS),
      stratum = interaction(YEAR, NIS_STRATUM),
      weight = DISCWT / 2,
      stay = LOS + 1
    )
  expect_true(anyDuplicated(unique(reference_data[c("YEAR", "HOSP_NIS")])$HOSP_NIS) > 0L)
  expect_true(any(table(unique(reference_data[c("psu", "stratum")])$stratum) == 1L))
  reference <- survey::svydesign(~psu, strata = ~stratum, weights = ~weight, data = reference_data, nest = TRUE)
  reference <- subset(reference, rare & HOSP_NIS %% 4L != 1L)
  expect_warning(
    base <- nis_design(query, rare, keep = c(LOS, predictor), annualize = TRUE),
    "invalid design fields"
  )
  domain <- base |>
    dplyr::filter(HOSP_NIS %% 4L != 1L) |>
    dplyr::mutate(stay = LOS + 1)
  expect_lt(nrow(domain$variables), nrow(base$variables))

  total <- survey::svytotal(~stay, domain)
  expected_total <- survey::svytotal(~stay, reference)
  ratio <- survey::svyratio(~stay, ~LOS, domain)
  expected_ratio <- survey::svyratio(~stay, ~LOS, reference)
  for (pair in list(list(total, expected_total), list(ratio, expected_ratio))) {
    expect_equal(coef(pair[[1L]]), coef(pair[[2L]]), tolerance = 1e-8)
    expect_equal(survey::SE(pair[[1L]]), survey::SE(pair[[2L]]), tolerance = 1e-8)
    expect_equal(confint(pair[[1L]]), confint(pair[[2L]]), tolerance = 1e-8)
  }
  expect_equal(survey::degf(domain), survey::degf(reference))
  fit <- survey::svyglm(stay ~ predictor, design = domain, na.action = stats::na.exclude)
  expected_fit <- survey::svyglm(stay ~ predictor, design = reference, na.action = stats::na.exclude)
  expect_equal(coef(fit), coef(expected_fit), tolerance = 1e-8)
  expect_equal(survey::SE(fit), survey::SE(expected_fit), tolerance = 1e-8)
  expect_equal(stats::df.residual(fit), stats::df.residual(expected_fit))
  expect_equal(confint(fit), confint(expected_fit), tolerance = 1e-8)

  info <- nis_design_report(domain)
  expect_equal(info$years, 2019:2020)
  expect_equal(info$input_n, nrow(full))
  expect_equal(info$excluded$total, sum(full$DISCWT <= 0))
  expect_equal(info$cohort_n, nrow(base$variables))
  expect_equal(info$domain_n, nrow(reference$variables))
  expect_identical(info$cohort, "rare")
  expect_true(info$annualize)
  expect_equal(info$divisor, 2)
  expect_identical(info$weight, "DISCWT")
  expect_identical(info$psu, c("YEAR", "HOSP_NIS"))
  expect_identical(info$strata, c("YEAR", "NIS_STRATUM"))
  expect_true(info$nest)
  model_info <- nis_design_report(fit)
  expect_equal(model_info$domain_n, info$domain_n)
  expect_gt(model_info$model$excluded_n, 0L)
  expect_equal(model_info$model$n, sum(!is.na(reference$variables$predictor)))
  expect_equal(model_info$model$n + model_info$model$excluded_n, info$domain_n)
  expect_output(print(model_info), "Fitted model")

  prefiltered <- nis_design(
    dplyr::filter(query, DISCWT > 0, rare, HOSP_NIS %% 4L != 1L),
    TRUE,
    keep = LOS,
    annualize = TRUE
  ) |>
    dplyr::mutate(stay = LOS + 1)
  wrong_total <- survey::svytotal(~stay, prefiltered)
  expect_equal(coef(wrong_total), coef(total), tolerance = 1e-8)
  expect_gt(abs(as.numeric(survey::SE(wrong_total) - survey::SE(total))), 1e-8)
  expect_lt(nis_design_report(prefiltered)$input_n, info$input_n)
})
