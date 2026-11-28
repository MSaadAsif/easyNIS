nis_annual_years <- function(sample, call) {
  years <- sort(union(sample$years, sample$excluded$by_year$YEAR))
  if (any(years != trunc(years) | years < 2012L)) {
    cli::cli_abort("Annual totals require whole calendar years from 2012 onward.", call = call)
  }
  complete <- sample$years[lengths(sample$coverage) == 4L]
  partial <- setdiff(years, complete)
  if (length(partial)) {
    cli::cli_abort(
      "All four discharge quarters must have valid design records in each input year. Check {.val {partial}}.",
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
        i = "Select complete years within one era, or document comparability and set `coding = \"verified_comparable\"`."
      ),
      call = call
    )
  }
  if (min(years) < 2015L && max(years) > 2015L) {
    cli::cli_abort("Select one coding era for annual totals spanning ICD-9-CM and ICD-10-CM/PCS years.", call = call)
  }
}

nis_check_2015_cohort <- function(quarters, call) {
  if (anyNA(quarters)) {
    cli::cli_abort("The 2015 cohort has missing or unrecognized discharge quarters.", call = call)
  }
  if (identical(quarters, 4L)) {
    cli::cli_abort("The 2015 cohort includes only ICD-10-CM/PCS discharges (Q4).", call = call)
  }
  if (length(quarters) && !4L %in% quarters) {
    cli::cli_abort("The 2015 cohort includes only ICD-9-CM discharges (Q1-Q3).", call = call)
  }
}

#' Estimate annual national discharge totals
#'
#' Estimate a weighted discharge total and design-based standard error for
#' each complete calendar year. Supply the annual sample and use `cohort` to
#' define the analysis domain. The calculation uses the original discharge
#' weights and year-specific hospital and stratum identifiers.
#'
#' @param .data A data frame or lazy DuckDB query with the standard NIS design
#'   fields and `DQTR` (quarter numbers or `Q1`–`Q4` labels). All four
#'   quarters must have valid design records in each year. This coverage check
#'   cannot verify that the sample is complete.
#' @param cohort Logical expression defining the domain, passed to [nis_design()].
#' @param coding Use `"single_era"` to require years within 2012–2014 or
#'   2016 onward. Use `"verified_comparable"` to acknowledge the transition and
#'   confirm that the definition is coding-independent or an audit found no
#'   coding discontinuity between 2015 Q3 and Q4. A 2015 cohort confined to
#'   one coding era or with unknown discharge quarters is rejected.
#'
#' @return A tibble ordered by `YEAR`, with `discharges`, `discharges_se`,
#'   unweighted `n`, and distinct contributing `hospitals`. Years without
#'   valid cohort discharges have zero support counts and missing estimates
#'   and standard errors. Use the support counts with [nis_suppress()] before
#'   sharing annual estimates.
#' @family survey-design
#' @seealso [Estimate trends across NIS years](https://msaadasif.github.io/easyNIS/articles/trends.html),
#'   [NIS output gallery](https://msaadasif.github.io/easyNIS/articles/gallery.html#annual-discharge-trend).
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2021)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' annual <- nis_annual_totals(nis, cohort = AGE >= 18 & heart_failure)
#' annual
#'
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   ggplot2::ggplot(annual, ggplot2::aes(YEAR, discharges)) +
#'     ggplot2::geom_line() +
#'     ggplot2::geom_point() +
#'     ggplot2::scale_x_continuous(breaks = annual$YEAR) +
#'     ggplot2::labs(x = "Discharge year", y = "Weighted discharges")
#' }
nis_annual_totals <- function(.data, cohort, coding = c("single_era", "verified_comparable")) {
  coding <- match.arg(coding)
  call <- rlang::current_call()
  if (missing(cohort)) {
    cli::cli_abort("Supply a logical `cohort` expression. Use `TRUE` for all discharges.", call = call)
  }
  if (!"DQTR" %in% nis_names(.data)) {
    cli::cli_abort("Annual totals require `DQTR`.", call = call)
  }
  data <- dplyr::ungroup(.data)
  saved <- !is.null(nis_saved_cohort(data, call))
  membership <- nis_cohort_membership(rlang::enquo(cohort), saved, call)
  nis_design_validate(data, "TOTCHG", FALSE, call, saved)
  data <- nis_design_input(data)
  fields <- nis_design_fields(data, rlang::quo(YEAR), call)
  prepared <- nis_design_prepare_fields(data)
  sample <- nis_sample_summary(prepared, fields$quarter_prototype, call, require_year = TRUE)
  years <- nis_annual_years(sample, call)
  if (coding == "single_era") {
    nis_check_coding_era(years, call)
  }
  domain <- dplyr::mutate(prepared, .nis_cohort = !!membership)
  domain <- nis_design_cohort_type(domain, call)
  domain <- dplyr::filter(domain, .nis_valid)
  if (2015L %in% years) {
    quarters <- domain |>
      dplyr::filter(YEAR == 2015L, .nis_cohort) |>
      dplyr::distinct(YEAR, DQTR) |>
      nis_collect()
    nis_check_2015_cohort(nis_cohort_2015_quarters(quarters), call)
  }
  nis_annual_summary(domain, sample$hospital_rows, years)
}

nis_annual_summary <- function(domain, hospital_rows, years) {
  grouped <- if (nis_design_duckdb(domain)) {
    nis_design_sql_tbl(domain, nis_annual_cells_sql(domain), c(.nis_survey_keys, "total", "n", "missing"))
  } else {
    nis_annual_cells_local(domain)
  }
  cells <- nis_collect(grouped)
  if (any(cells$missing > 0L)) {
    cli::cli_inform("Treated missing cohort values as outside the cohort.")
  }
  nis_annual_estimates(cells, hospital_rows, years)
}

nis_annual_cells_sql <- function(domain) {
  sprintf(
    paste(
      'SELECT "YEAR", "NIS_STRATUM", "HOSP_NIS",',
      'sum(CASE WHEN ".nis_cohort" THEN CAST("DISCWT" AS DOUBLE) ELSE 0.0 END) AS "total",',
      'count(*) FILTER (WHERE ".nis_cohort") AS "n",',
      'count(*) FILTER (WHERE ".nis_cohort" IS NULL) AS "missing"',
      "FROM (%s) AS domain GROUP BY 1, 2, 3"
    ),
    dbplyr::sql_render(domain)
  )
}

nis_annual_cells_local <- function(domain) {
  domain |>
    dplyr::group_by(YEAR, NIS_STRATUM, HOSP_NIS) |>
    dplyr::summarise(
      total = sum(dplyr::if_else(dplyr::coalesce(.nis_cohort, FALSE), as.double(DISCWT), 0), na.rm = TRUE),
      n = sum(dplyr::coalesce(.nis_cohort, FALSE), na.rm = TRUE),
      missing = sum(is.na(.nis_cohort), na.rm = TRUE),
      .groups = "drop"
    )
}

nis_annual_estimates <- function(cells, hospital_rows, years) {
  cells <- cells[cells$n > 0, ]
  absent <- setdiff(years, cells$YEAR)
  if (length(absent)) {
    cli::cli_warn("No cohort discharges in {cli::qty(length(absent))}year{?s} {.val {absent}}.")
  }
  roster <- nis_survey_roster_sizes(hospital_rows)
  cells$psu <- vctrs::vec_match(cells[.nis_survey_keys], roster[.nis_survey_keys])
  annual <- dplyr::tibble(YEAR = years, discharges = NA_real_, discharges_se = NA_real_, n = 0L, hospitals = 0L)
  for (rows in split(seq_len(nrow(cells)), match(cells$YEAR, years))) {
    i <- match(cells$YEAR[rows[1L]], years)
    scores <- cells$total[rows]
    # Keep only contributing PSUs. Survey pads their sampled strata with
    # zero scores, including when only one PSU contributes to the domain.
    variance <- nis_survey_variance(
      matrix(scores),
      cells$psu[rows],
      roster,
      lonely.psu = getOption("survey.lonely.psu", "fail")
    )
    annual$discharges[i] <- sum(scores)
    annual$discharges_se[i] <- sqrt(variance[1L, 1L])
    annual$n[i] <- as.integer(sum(as.numeric(cells$n[rows])))
    annual$hospitals[i] <- length(rows)
  }
  annual
}
