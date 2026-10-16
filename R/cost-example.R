.cpi_u <- dplyr::tribble(
  ~year, ~index,
  2012, 229.594,
  2013, 232.957,
  2014, 236.736,
  2015, 237.017,
  2016, 240.007,
  2017, 245.120,
  2018, 251.107,
  2019, 255.657,
  2020, 258.811,
  2021, 270.970,
  2022, 292.655,
  2023, 304.702,
  2024, 313.689
)
attr(.cpi_u, "source") <- paste(
  "U.S. Bureau of Labor Statistics, CPI-U All items, U.S. city average,",
  "not seasonally adjusted, series CUUR0000SA0; annual averages"
)

#' Adjust NIS charges and costs to a reference dollar year
#'
#' @param data A data frame with `YEAR`, `TOTCHG`, and `CCR_NIS`.
#' @param dollars Reference dollar year, from 2012 through 2024.
#'
#' @return `data` with `cost_adj` and `charges_adj` in `dollars` USD.
#' @export
#' @examples
#' charges <- nis_open(nis_example(years = 2019:2020)) |>
#'   dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
#'   dplyr::collect()
#' head(nis_cost(charges, dollars = 2024))
nis_cost <- function(data, dollars) {
  required <- c("YEAR", "TOTCHG", "CCR_NIS")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort("`data` is missing required column{?s} {.val {missing}}.")
  }
  if (length(dollars) != 1L || !is.numeric(dollars) || is.na(dollars) ||
      dollars != as.integer(dollars) || !dollars %in% .cpi_u$year) {
    cli::cli_abort("`dollars` must be one year from 2012 through 2024.")
  }
  if (!is.numeric(data$YEAR) || !is.numeric(data$TOTCHG) ||
      !is.numeric(data$CCR_NIS)) {
    cli::cli_abort("`YEAR`, `TOTCHG`, and `CCR_NIS` must be numeric.")
  }
  index <- match(data$YEAR, .cpi_u$year)
  if (anyNA(index)) {
    cli::cli_abort("`YEAR` contains values without a CPI-U index (2012-2024).")
  }

  reference_index <- .cpi_u$index[match(as.integer(dollars), .cpi_u$year)]
  data$cost_adj <- data$TOTCHG * data$CCR_NIS * reference_index / .cpi_u$index[index]
  data$charges_adj <- data$TOTCHG * reference_index / .cpi_u$index[index]
  attr(data$cost_adj, "label") <- paste0("Hospital cost (", dollars, " USD)")
  attr(data$charges_adj, "label") <- paste0("Total charges (", dollars, " USD)")
  data
}

#' Write an invented NIS-shaped Parquet dataset
#'
#' @param years Years to create, from 2016 through 2024.
#'
#' @return The temporary directory containing `NIS_<year>.parquet/` entries.
#' @export
#' @examples
#' path <- nis_example(years = 2019:2020)
#' list.files(path)
nis_example <- function(years = 2017:2022) {
  if (!is.numeric(years) || length(years) == 0L || anyNA(years) ||
      any(years != as.integer(years)) || any(years < 2016L) || any(years > 2024L)) {
    cli::cli_abort("`years` must contain whole years from 2016 through 2024.")
  }
  years <- unique(as.integer(years))
  path <- tempfile("nis-example-")
  dir.create(path)

  for (year in years) {
    stratum <- rep(1:3, each = 4L)
    hospital <- rep(1:12, each = 8L)
    hospital_stratum <- stratum[hospital]
    within_hospital <- rep(1:8, times = 12L)
    n <- length(hospital)
    has_cohort <- hospital %% 4L != 0L & within_hospital %% 3L != 0L

    records <- dplyr::tibble(
      YEAR = rep(year, n),
      HOSP_NIS = hospital,
      NIS_STRATUM = hospital_stratum,
      DISCWT = 1 + (hospital %% 5L) / 10,
      CCR_NIS = 0.28 + (hospital %% 4L) / 100,
      TOTCHG = 12000 + year + hospital * 100 + within_hospital * 35,
      LOS = (hospital + within_hospital) %% 12,
      DIED = as.integer((hospital + within_hospital) %% 19L == 0L),
      AGE = 18 + (hospital * 3 + within_hospital * 7) %% 75,
      FEMALE = as.integer((hospital + within_hospital) %% 2L == 0L),
      RACE = (hospital + within_hospital) %% 6L + 1L,
      PAY1 = (hospital + within_hospital) %% 6L + 1L,
      ZIPINC_QRTL = (hospital + within_hospital) %% 4L + 1L,
      AWEEKEND = as.integer(within_hospital %in% c(6L, 7L)),
      AMONTH = (within_hospital + hospital) %% 12L + 1L,
      TRAN_IN = (hospital + within_hospital) %% 3L,
      TRAN_OUT = (hospital + within_hospital + 1L) %% 3L,
      DISPUNIFORM = c(1, 2, 5, 6, 7, 20, 21, 99)[within_hospital],
      HCUP_ED = (hospital + within_hospital) %% 6L,
      ELECTIVE = as.integer(within_hospital %% 4L == 0L),
      AGE_NEONATE = 0L,
      PL_NCHS = (hospital %% 6L) + 1L,
      DQTR = ((within_hospital - 1L) %% 4L) + 1L,
      HOSP_DIVISION = (hospital_stratum - 1L) * 3L + 1L,
      HOSP_REGION = hospital_stratum + 1L,
      HOSP_BEDSIZE = (hospital %% 3L) + 1L,
      H_CONTRL = (hospital %% 3L) + 1L,
      HOSP_LOCTEACH = (hospital %% 3L) + 1L,
      I10_NDX = 2L,
      I10_NPR = 1L,
      I10_BIRTH = 0L,
      I10_DELIVERY = 0L,
      I10_INJURY = as.integer(within_hospital %% 5L == 0L),
      I10_MULTINJURY = 0L,
      I10_SERVICELINE = 1L,
      PCLASS_ORPROC = 1L,
      elixsum = as.numeric((hospital + within_hospital) %% 4L),
      ynel1 = as.integer((hospital + within_hospital) %% 2L == 0L),
      ynel2 = as.integer((hospital + within_hospital) %% 3L == 0L)
    )
    records$I10_DX1 <- ifelse(has_cohort, "I5022", "J189")
    exposure_code <- (hospital + within_hospital) %% 5L == 0L
    records$I10_DX2 <- ifelse(exposure_code, "Z515",
      ifelse(has_cohort & within_hospital %% 2L == 1L, "I509", "E119"))
    records$I10_PR1 <- ifelse(within_hospital %% 2L == 0L, "0JH60DZ", "02703ZZ")
    records$I10_PR2 <- ifelse(within_hospital %% 3L == 0L, "02L73DK", NA_character_)
    for (slot in 3:40) records[[paste0("I10_DX", slot)]] <- NA_character_
    for (slot in 3:25) records[[paste0("I10_PR", slot)]] <- NA_character_

    mortality_name <- if (year == 2022L) {
      "APRDRG_RISK_MORTALITY"
    } else {
      "APRDRG_Risk_Mortality"
    }
    severity_name <- if (year == 2022L) {
      "APRDRG_SEVERITY"
    } else {
      "APRDRG_Severity"
    }
    records[[mortality_name]] <- (hospital + within_hospital) %% 5L
    records[[severity_name]] <- (hospital + within_hospital + 1L) %% 5L
    records[[if (year == 2022L) "DRG_NOPOA" else "DRG_NoPOA"]] <- 100L + hospital
    records[[if (year == 2022L) "MDC_NOPOA" else "MDC_NoPOA"]] <- hospital_stratum

    year_path <- file.path(path, paste0("NIS_", year, ".parquet"))
    dir.create(year_path)
    arrow::write_parquet(records, file.path(year_path, "part-0.parquet"))
  }
  path
}
