comparison_designs <- function(years = 2017:2019, partial_2015 = FALSE,
                               annualize = FALSE, invalid_rows = FALSE) {
  path <- nis_example(years)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")

  data <- query |>
    dplyr::collect()
  if (invalid_rows) {
    data$DISCWT[1L] <- -1
  }
  valid <- with(data, is.finite(YEAR) & YEAR > 0 & is.finite(HOSP_NIS) &
    HOSP_NIS > 0 & is.finite(NIS_STRATUM) & NIS_STRATUM > 0 &
    is.finite(DISCWT) & DISCWT > 0)
  cohort <- dplyr::coalesce(data$heart_failure, FALSE)
  if (partial_2015) cohort <- cohort & (data$YEAR != 2015L | data$DQTR == 4L)
  year_count <- length(unique(data$YEAR[valid]))
  full_data <- data[valid, , drop = FALSE] |>
    dplyr::mutate(.in_cohort = cohort[valid]) |>
    dplyr::select(
      YEAR, HOSP_NIS, NIS_STRATUM, DISCWT, .in_cohort,
      AGE, DIED, LOS, FEMALE, RACE, PAY1 # nolint
    ) |>
    dplyr::collect()
  full_data$.nis_psu <- paste(full_data$YEAR, full_data$HOSP_NIS, sep = "::")
  full_data$.nis_stratum <- paste(full_data$YEAR, full_data$NIS_STRATUM, sep = "::")
  full_data$.nis_weight <- full_data$DISCWT
  full_unannualized_data <- full_data
  full_data$.nis_weight <- full_data$.nis_weight / if (annualize) year_count else 1
  full_data <- nis_label(full_data)
  full_unannualized_data <- nis_label(full_unannualized_data)

  full_design <- srvyr::as_survey_design(
    full_data,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)

  full_unannualized_design <- srvyr::as_survey_design(
    full_unannualized_data,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)

  placeholder_design <- nis_design(
    data,
    if (partial_2015) heart_failure & (YEAR != 2015L | DQTR == 4L) else heart_failure, # nolint
    keep = c(AGE, DIED, LOS, FEMALE, RACE, PAY1, YEAR, DQTR), # nolint
    annualize = annualize
  )

  list(
    path = path,
    query = query,
    full_data = full_data,
    full = full_design,
    full_unannualized = full_unannualized_design,
    placeholder = placeholder_design
  )
}
