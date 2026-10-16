comparison_designs <- function(years = 2017:2019) {
  path <- nis_example(years)
  query <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")

  full_data <- query |>
    dplyr::mutate(.in_cohort = dplyr::coalesce(heart_failure, FALSE)) |>
    dplyr::select(
      YEAR, HOSP_NIS, NIS_STRATUM, DISCWT, .in_cohort,
      AGE, DIED, LOS, FEMALE, RACE, PAY1
    ) |>
    dplyr::collect()
  full_data$.nis_psu <- paste(full_data$YEAR, full_data$HOSP_NIS, sep = "::")
  full_data$.nis_stratum <- paste(full_data$YEAR, full_data$NIS_STRATUM, sep = "::")
  full_data$.nis_weight <- full_data$DISCWT
  full_data <- nis_label(full_data)

  full_design <- srvyr::as_survey_design(
    full_data,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)

  placeholder_design <- nis_design(
    query,
    heart_failure,
    keep = c(AGE, DIED, LOS, FEMALE, RACE, PAY1, YEAR)
  )

  list(
    path = path,
    query = query,
    full_data = full_data,
    full = full_design,
    placeholder = placeholder_design
  )
}
