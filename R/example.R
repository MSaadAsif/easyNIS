.nis_example_validate_years <- function(years) {
  if (!is.numeric(years) || length(years) == 0L || anyNA(years)) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.", call = rlang::caller_call())
  }
  if (!all(is.finite(years)) || any(years != as.integer(years))) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.", call = rlang::caller_call())
  }
  if (any(years < 2012L) || any(years > 2024L)) {
    cli::cli_abort("`years` must contain whole years from 2012 through 2024.", call = rlang::caller_call())
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
    KEY_NIS = seq_along(hospital),
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
  list(
    records = records,
    hospital = hospital,
    hospital_stratum = hospital_stratum,
    within_hospital = within_hospital,
    has_cohort = has_cohort
  )
}

.nis_example_add_code_slots <- function(records, hospital, within_hospital, has_cohort) {
  records$I10_DX1 <- ifelse(has_cohort, "I5022", "J189")
  exposure_code <- (hospital + within_hospital) %% 5L == 0L
  records$I10_DX2 <- ifelse(exposure_code, "Z515", ifelse(has_cohort & within_hospital %% 2L == 1L, "I509", "E119"))
  records$I10_PR1 <- ifelse(within_hospital %% 2L == 0L, "0JH60DZ", "02703ZZ")
  records$I10_PR2 <- ifelse(within_hospital %% 3L == 0L, "02L73DK", NA_character_)
  for (slot in 3:40) {
    records[[paste0("I10_DX", slot)]] <- NA_character_
  }
  for (slot in 3:25) {
    records[[paste0("I10_PR", slot)]] <- NA_character_
  }
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
    for (slot in 3:30) {
      records[[paste0("DX", slot)]] <- NA_character_
    }
    for (slot in 2:15) {
      records[[paste0("PR", slot)]] <- NA_character_
    }
    records$NDX <- ifelse(is_icd9, 2L, NA_integer_)
    records$NPR <- ifelse(is_icd9, 1L, NA_integer_)
    icd10_columns <- grep("^I10_", names(records), value = TRUE)
    for (column in icd10_columns) {
      records[[column]][is_icd9] <- NA
    }
    if (year < 2015L) {
      records <- dplyr::select(records, -dplyr::all_of(icd10_columns))
      records <- dplyr::select(records, -dplyr::all_of(paste0("DX", 26:30)))
    } else {
      records <- dplyr::select(
        records,
        -dplyr::all_of(c(
          paste0("I10_DX", 31:40),
          paste0("I10_PR", 16:25)
        ))
      )
    }
  }
  records
}

.nis_example_annual_fields <- function(records, year, hospital, hospital_stratum, within_hospital) {
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
    fixture$records,
    fixture$hospital,
    fixture$within_hospital,
    fixture$has_cohort
  )
  records <- .nis_example_pre2016_layout(
    records,
    year,
    fixture$has_cohort
  )
  .nis_example_annual_fields(
    records,
    year,
    fixture$hospital,
    fixture$hospital_stratum,
    fixture$within_hospital
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
  if (!dir.create(path, mode = "0700")) {
    cli::cli_abort("Could not create a temporary NIS example directory.")
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  complete <- FALSE
  on.exit(if (!complete) nis_remove_owned_directory(path))

  con <- nis_duckdb_connect(config = list(threads = "1"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE, after = FALSE)
  for (year in years) {
    year_path <- file.path(path, paste0("NIS_", year, ".parquet"))
    if (!dir.create(year_path)) {
      cli::cli_abort("Could not create an example year directory.")
    }
    nis_duckdb_write_parquet(.nis_example_records(year), file.path(year_path, "part-0.parquet"), con)
  }
  complete <- TRUE
  path
}
