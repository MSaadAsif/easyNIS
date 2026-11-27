nis_annual_years <- function(.data, call) {
  required <- c("YEAR", "DQTR")
  missing <- setdiff(required, nis_names(.data))
  if (length(missing)) {
    cli::cli_abort("Annual totals require {.field {missing}}.", call = call)
  }
  quarters <- as.character(1:4)
  periods <- .data |>
    dplyr::transmute(
      YEAR = .data$YEAR,
      DQTR = dplyr::if_else(.data$DQTR %in% quarters, .data$DQTR, NA)
    ) |>
    dplyr::distinct() |>
    nis_collect()

  years <- sort(unique(periods$YEAR))
  if (!length(years) || !is.numeric(years) || any(!is.finite(years) | years != trunc(years) | years < 2012L)) {
    cli::cli_abort("Annual totals require whole calendar years from 2012 onward.", call = call)
  }
  coverage <- periods |>
    dplyr::filter(!is.na(.data$DQTR)) |>
    dplyr::count(.data$YEAR)
  partial <- setdiff(years, coverage$YEAR[coverage$n == 4L])
  if (length(partial)) {
    cli::cli_abort(
      "All four discharge quarters must be present in each input year. Check {.val {partial}}.",
      call = call
    )
  }
  years
}

nis_check_coding_era <- function(years, call) {
  if (2015L %in% years) {
    cli::cli_abort(
      c(
        "2015 spans the ICD-9-CM to ICD-10-CM/PCS transition.",
        i = "Select complete years on one side, or use `coding = \"independent\"` for a coding-independent analysis."
      ),
      call = call
    )
  }
  if (min(years) < 2015L && max(years) > 2015L) {
    cli::cli_abort("Select one coding era for annual totals spanning ICD-9-CM and ICD-10-CM/PCS years.", call = call)
  }
}

#' Estimate annual national discharge totals
#'
#' Estimates one national total and design-based standard error per calendar
#' year using unscaled discharge weights. Give the function the annual sample
#' and declare the analysis domain with `cohort`. The design uses year-specific
#' hospital and stratum identifiers, as in [nis_design()].
#'
#' @param .data A data frame or lazy DuckDB query with the standard NIS design
#'   fields and `DQTR`. All four discharge quarters must be represented in
#'   each year. This coverage check cannot verify that the sample is complete.
#' @param cohort Logical expression defining the domain, passed to [nis_design()].
#' @param coding Use `"single_era"` to require years within 2012–2014 or
#'   2016 onward. Use `"independent"` if both the cohort definition and the
#'   analysis are independent of diagnosis and procedure coding. This allows
#'   complete 2015 data and spanning the ICD transition.
#'
#' @return A tibble ordered by `YEAR`, with `discharges` and `discharges_se`.
#'   Input years without valid cohort discharges have missing estimates and
#'   standard errors. Apply disclosure rules before sharing annual estimates.
#' @seealso [Trends](articles/trends.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' nis_annual_totals(nis, heart_failure)
nis_annual_totals <- function(.data, cohort, coding = c("single_era", "independent")) {
  coding <- match.arg(coding)
  .data <- dplyr::ungroup(.data)
  call <- rlang::current_call()
  years <- nis_annual_years(.data, call)
  if (coding == "single_era") {
    nis_check_coding_era(years, call)
  }
  design <- nis_design(.data, {{ cohort }}, keep = YEAR, annualize = FALSE)
  annual <- dplyr::tibble(YEAR = years)
  if (nrow(design$variables) == 0L) {
    return(dplyr::mutate(annual, discharges = NA_real_, discharges_se = NA_real_))
  }
  totals <- design |>
    dplyr::group_by(.data$YEAR) |>
    dplyr::summarise(discharges = srvyr::survey_total(), .groups = "drop")
  dplyr::left_join(annual, totals, by = "YEAR")
}
