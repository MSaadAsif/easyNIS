test_that("input grouping does not change cohort evaluation or survey estimates", {
  data <- expand.grid(discharge = 1:3, hospital = 1:6, YEAR = 2020:2021)
  data$HOSP_NIS <- data$hospital
  data$NIS_STRATUM <- ceiling(data$hospital / 3)
  data$DISCWT <- 2 + seq_len(nrow(data)) / 10
  data$LOS <- data$discharge + data$hospital + 2 * (data$YEAR - 2020)
  data$eligible <- data$hospital %% 3 != 0
  data$unused_group <- data$hospital %% 2
  data$psu <- paste(data$YEAR, data$HOSP_NIS, sep = "::")
  data$stratum <- paste(data$YEAR, data$NIS_STRATUM, sep = "::")
  data$weight <- data$DISCWT / 2

  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  lazy <- dplyr::copy_to(con, data, "invented_grouping", temporary = TRUE)
  groupings <- list("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "LOS",
    c("YEAR", "LOS"), "unused_group")
  inputs <- c(list(data, lazy, dplyr::rowwise(data),
    dplyr::rowwise(data, YEAR)),
    lapply(groupings, function(fields) {
      dplyr::group_by(data, dplyr::across(dplyr::all_of(fields)))
    }),
    lapply(groupings, function(fields) {
      dplyr::group_by(lazy, dplyr::across(dplyr::all_of(fields)))
    }))

  for (aggregate_cohort in c(FALSE, TRUE)) {
    in_cohort <- if (aggregate_cohort) {
      data$eligible & data$LOS > mean(data$LOS)
    } else {
      rep(TRUE, nrow(data))
    }
    full <- survey::svydesign(~psu, strata = ~stratum, weights = ~weight,
      data = data, nest = TRUE)
    reference <- full[in_cohort, ]
    for (input in inputs) {
      actual <- nis_design(input,
        if (aggregate_cohort) eligible & LOS > mean(LOS) else TRUE,
        keep = LOS, annualize = TRUE)
      expect_equal(nrow(actual$variables), sum(in_cohort))
      expect_equal(sort(actual$variables$LOS), sort(data$LOS[in_cohort]))
      expect_setequal(names(actual$variables), c("YEAR", "HOSP_NIS",
        "NIS_STRATUM", "DISCWT", "LOS", ".in_cohort", ".nis_psu",
        ".nis_stratum", ".nis_weight"))
      expect_length(dplyr::group_vars(actual), 0L)
      expect_equal(survey::degf(actual), survey::degf(reference))
      for (estimate in list(survey::svymean, survey::svytotal)) {
        observed <- estimate(~LOS, actual)
        expected <- estimate(~LOS, reference)
        expect_equal(coef(observed), coef(expected), tolerance = 1e-10)
        expect_equal(vcov(observed), vcov(expected), tolerance = 1e-10)
      }
      grouped <- dplyr::group_by(actual, YEAR)
      expect_identical(dplyr::group_vars(grouped), "YEAR")
      expect_equal(nrow(srvyr::summarise(grouped,
        total = srvyr::survey_total())), 2L)
    }
  }
})
