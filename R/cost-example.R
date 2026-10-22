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

.nis_cost_inform_invalid_ccr <- function(count, cohort = FALSE) {
  if (count > 0L) {
    row_type <- if (cohort) " cohort row" else " row"
    count_text <- paste0(
      count, row_type,
      if (count == 1L) " has" else "s have"
    )
    cli::cli_inform(paste0(
      count_text,
      " missing or invalid `CCR_NIS`; `cost_adj` is `NA` for these rows."
    ))
  }
}

.nis_cost_validate_data <- function(data) {
  if (!is.data.frame(data)) {
    cli::cli_abort("`data` must be a collected data frame.")
  }
}

.nis_cost_validate_charge_name <- function(charges) {
  if (!is.character(charges) || length(charges) != 1L || is.na(charges)) {
    cli::cli_abort("`charges` must be a single column name.")
  }
}

.nis_cost_validate_columns <- function(data, charges) {
  required <- c("YEAR", charges, "CCR_NIS")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort("`data` is missing required column{?s} {.val {missing}}.")
  }
}

.nis_cost_validate_dollars <- function(dollars) {
  if (length(dollars) != 1L || !is.numeric(dollars) || is.na(dollars)) {
    cli::cli_abort("`dollars` must be one year from 2012 through 2024.")
  }
  if (dollars != as.integer(dollars) || !dollars %in% .cpi_u$year) {
    cli::cli_abort("`dollars` must be one year from 2012 through 2024.")
  }
}

.nis_cost_validate_numeric <- function(data, charges) {
  if (!is.numeric(data$YEAR) || !is.numeric(data[[charges]]) ||
      !is.numeric(data$CCR_NIS)) {
    cli::cli_abort("`YEAR`, {.field {charges}}, and `CCR_NIS` must be numeric.")
  }
}

.nis_cost_year_index <- function(year) {
  index <- match(year, .cpi_u$year)
  if (anyNA(index)) {
    cli::cli_abort("`YEAR` contains values without a CPI-U index (2012-2024).")
  }
  index
}

.nis_cost_provenance <- function(charges, dollars, multipliers,
                                 invalid_ccr_count, missing_charges_count) {
  list(
    charge_field = charges,
    ccr_field = "CCR_NIS",
    inflation_index = "CPI-U All items, U.S. city average (annual average)",
    inflation_index_source = attr(.cpi_u, "source", exact = TRUE),
    base_year = as.integer(dollars),
    multipliers = multipliers,
    rows_missing_or_invalid_ccr = invalid_ccr_count,
    rows_missing_charges = missing_charges_count,
    ccr_treatment = paste0(
      "Missing, non-finite, zero, or negative CCR_NIS values produce ",
      "NA cost_adj; charges_adj is retained."
    ),
    output_types = c(
      charges_adj = "Inflation-adjusted charges",
      cost_adj = "Estimated cost via CCR_NIS"
    )
  )
}

#' Adjust NIS charges and costs to a reference dollar year
#'
#' @param data A collected data frame with `YEAR`, the `charges` column, and
#'   `CCR_NIS`. Lazy Arrow and DuckDB queries must be collected first.
#' @param dollars Reference dollar year, from 2012 through 2024.
#' @param charges Name of the total-charge column. Defaults to `"TOTCHG"`.
#'   Use `"TOTCHG_2023"` only knowingly: HCUP adjusts that field for states
#'   missing from 2023, so it is not comparable to earlier-year `TOTCHG`, and it
#'   is missing for earlier years.
#'
#' @return `data` with `cost_adj` and `charges_adj` in `dollars` USD. The
#'   in-memory data frame has `nis_cost_provenance` metadata; retrieve it with
#'   [nis_cost_provenance()].
#' @family costs
#' @seealso [Charges, costs, and provenance](articles/costs.html).
#' @export
#' @examples
#' charges <- nis_open(nis_example(years = 2019:2020)) |>
#'   dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
#'   dplyr::collect()
#' head(nis_cost(charges, dollars = 2024))
nis_cost <- function(data, dollars, charges = "TOTCHG") {
  .nis_cost_validate_data(data)
  .nis_cost_validate_charge_name(charges)
  .nis_cost_validate_columns(data, charges)
  .nis_cost_validate_dollars(dollars)
  .nis_cost_validate_numeric(data, charges)
  index <- .nis_cost_year_index(data$YEAR)

  reference_index <- .cpi_u$index[match(as.integer(dollars), .cpi_u$year)]
  ccr <- data$CCR_NIS
  valid_ccr <- is.finite(ccr) & ccr > 0
  invalid_ccr_count <- sum(!dplyr::coalesce(valid_ccr, FALSE))
  charges_value <- data[[charges]]
  valid_charges <- is.finite(charges_value)
  missing_charges_count <- sum(!dplyr::coalesce(valid_charges, FALSE))
  data$cost_adj <- ifelse(valid_ccr & valid_charges,
    charges_value * ccr * reference_index / .cpi_u$index[index], NA_real_)
  data$charges_adj <- ifelse(valid_charges,
    charges_value * reference_index / .cpi_u$index[index], NA_real_)
  attr(data$cost_adj, "label") <- paste0("Hospital cost (", dollars, " USD)")
  attr(data$charges_adj, "label") <- paste0("Total charges (", dollars, " USD)")
  multipliers <- data.frame(
    year = .cpi_u$year[.cpi_u$year %in% unique(data$YEAR)],
    multiplier = reference_index /
      .cpi_u$index[.cpi_u$year %in% unique(data$YEAR)],
    stringsAsFactors = FALSE
  )
  provenance <- .nis_cost_provenance(
    charges, dollars, multipliers, invalid_ccr_count, missing_charges_count
  )
  attr(data, "nis_cost_provenance") <- provenance
  .nis_cost_inform_invalid_ccr(invalid_ccr_count)
  data
}

#' Read cost adjustment provenance
#'
#' Returns the metadata recorded by [nis_cost()] or [nis_design()] when cost
#' adjustment was requested. Data frame operations may drop custom attributes;
#' call this on the direct `nis_cost()` result or on the survey design returned
#' by `nis_design()`.
#'
#' @param x A data frame returned by [nis_cost()] or a survey design returned
#'   by [nis_design()].
#'
#' @return A list describing the charge and CCR fields, CPI-U source and base
#'   year, annual multipliers, invalid CCR and missing charge counts, and output
#'   meanings. Returns `NULL` when no cost adjustment provenance is present.
#' @family costs
#' @seealso [Charges, costs, and provenance](articles/costs.html).
#' @examples
#' charges <- nis_open(nis_example(years = 2019)) |>
#'   dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
#'   dplyr::collect() |>
#'   nis_cost(dollars = 2024)
#' nis_cost_provenance(charges)
#' @export
nis_cost_provenance <- function(x) {
  if (!is.data.frame(x) && !inherits(x, "tbl_svy")) {
    cli::cli_abort("`x` must be a data frame or survey design.")
  }
  attr(x, "nis_cost_provenance", exact = TRUE)
}

.nis_example_validate_years <- function(years) {
  if (!is.numeric(years) || length(years) == 0L || anyNA(years)) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.")
  }
  if (any(!is.finite(years)) || any(years != as.integer(years))) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.")
  }
  if (any(years < 2012L) || any(years > 2024L)) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.")
  }
}

.nis_example_base_records <- function(year) {
  stratum <- rep(1:3, each = 4L)
  hospital <- rep(1:12, each = 8L)
  hospital_stratum <- stratum[hospital]
  within_hospital <- rep(1:8, times = 12L)
  has_cohort <- hospital %% 4L != 0L & within_hospital %% 3L != 0L
  records <- dplyr::tibble(
    YEAR = rep(year, length(hospital)),
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
  list(records = records, hospital = hospital,
    hospital_stratum = hospital_stratum,
    within_hospital = within_hospital, has_cohort = has_cohort)
}

.nis_example_add_code_slots <- function(records, hospital, within_hospital,
                                        has_cohort) {
  records$I10_DX1 <- ifelse(has_cohort, "I5022", "J189")
  exposure_code <- (hospital + within_hospital) %% 5L == 0L
  records$I10_DX2 <- ifelse(exposure_code, "Z515",
    ifelse(has_cohort & within_hospital %% 2L == 1L, "I509", "E119"))
  records$I10_PR1 <- ifelse(within_hospital %% 2L == 0L, "0JH60DZ", "02703ZZ")
  records$I10_PR2 <- ifelse(within_hospital %% 3L == 0L, "02L73DK", NA_character_)
  for (slot in 3:40) records[[paste0("I10_DX", slot)]] <- NA_character_
  for (slot in 3:25) records[[paste0("I10_PR", slot)]] <- NA_character_
  records
}

.nis_example_pre2016_layout <- function(records, year, has_cohort) {
  if (year < 2016L) {
    is_icd9 <- year < 2015L | records$DQTR <= 3L
    records$DXVER <- ifelse(is_icd9, 9L, 10L)
    records$PRVER <- records$DXVER
    records$DX1 <- ifelse(is_icd9, ifelse(has_cohort, "12345", "67890"), NA_character_)
    records$DX2 <- ifelse(is_icd9, "V0001", NA_character_)
    records$PR1 <- ifelse(is_icd9, "0123", NA_character_)
    for (slot in 3:30) records[[paste0("DX", slot)]] <- NA_character_
    for (slot in 2:15) records[[paste0("PR", slot)]] <- NA_character_
    records$NDX <- ifelse(is_icd9, 2L, NA_integer_)
    records$NPR <- ifelse(is_icd9, 1L, NA_integer_)
    icd10_columns <- grep("^I10_", names(records), value = TRUE)
    for (column in icd10_columns) records[[column]][is_icd9] <- NA
    if (year < 2015L) {
      records <- dplyr::select(records, -dplyr::all_of(icd10_columns))
      records <- dplyr::select(records, -dplyr::all_of(paste0("DX", 26:30)))
    } else {
      records <- dplyr::select(records, -dplyr::all_of(c(
        paste0("I10_DX", 31:40), paste0("I10_PR", 16:25)
      )))
    }
  }
  records
}

.nis_example_add_annual_fields <- function(records, year, hospital,
                                           hospital_stratum, within_hospital) {
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
  records
}

.nis_example_records <- function(year) {
  fixture <- .nis_example_base_records(year)
  records <- .nis_example_add_code_slots(
    fixture$records, fixture$hospital, fixture$within_hospital,
    fixture$has_cohort
  )
  records <- .nis_example_pre2016_layout(
    records, year, fixture$has_cohort
  )
  .nis_example_add_annual_fields(
    records, year, fixture$hospital, fixture$hospital_stratum,
    fixture$within_hospital
  )
}

.nis_example_write_year <- function(path, year) {
  year_path <- file.path(path, paste0("NIS_", year, ".parquet"))
  dir.create(year_path)
  arrow::write_parquet(
    .nis_example_records(year), file.path(year_path, "part-0.parquet")
  )
}

#' Write an invented NIS-shaped Parquet dataset
#'
#' @param years Years to create, from 2012 through 2024. Years before 2016
#'   are experimental. The 2015 fixture has separate ICD-9 and ICD-10 slots,
#'   with invented codes and version indicators; it is not a clinical crosswalk.
#'
#' @return The temporary directory containing `NIS_<year>.parquet/` entries.
#' @family data-access
#' @seealso [Opening NIS data](articles/opening-data.html).
#' @export
#' @examples
#' path <- nis_example(years = 2019:2020)
#' list.files(path)
nis_example <- function(years = 2017:2022) {
  .nis_example_validate_years(years)
  years <- unique(as.integer(years))
  path <- tempfile("nis-example-")
  dir.create(path)
  for (year in years) .nis_example_write_year(path, year)
  path
}
