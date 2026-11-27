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
