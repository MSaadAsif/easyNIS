published_total <- function(design) {
  if (nrow(design$variables) <= 10L) {
    stop("The sample is below the HCUP disclosure threshold.", call. = FALSE)
  }
  total <- survey::svytotal(~discharge, design)
  list(estimate = unname(stats::coef(total)[[1L]]), se = unname(survey::SE(total)[[1L]]))
}

published_all <- function(data_root) {
  easyNIS::nis_open(data_root, years = 2022L) |>
    dplyr::mutate(discharge = 1) |>
    easyNIS::nis_design(cohort = TRUE, keep = discharge) |>
    published_total()
}

published_adult <- function(data_root) {
  easyNIS::nis_open(data_root, years = 2019L) |>
    dplyr::mutate(discharge = 1) |>
    easyNIS::nis_design(cohort = AGE >= 18L, keep = discharge) |>
    published_total()
}

published_covid <- function(data_root) {
  easyNIS::nis_open(data_root, years = 2020:2021) |>
    easyNIS::nis_flag_dx(covid = list(regex = "U071"), position = "any") |>
    dplyr::mutate(discharge = 1) |>
    easyNIS::nis_design(
      cohort = covid & (YEAR == 2021L | DQTR %in% c(2L, 3L, 4L)),
      keep = discharge
    ) |>
    published_total()
}

published_estimands <- function(data_root) {
  list(
    "hcup-2022-all" = published_all(data_root),
    "hcup-2019-adult" = published_adult(data_root),
    "matsuzaki-covid" = published_covid(data_root)
  )
}
