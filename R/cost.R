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

nis_cost_report <- function(provenance, population) {
  messages <- c(
    rows_missing_or_invalid_ccr =
      "missing or invalid `CCR_NIS`; `cost_adj` is `NA` for these rows.",
    rows_missing_charges =
      "missing or invalid charges; `charges_adj` and `cost_adj` are `NA` for these rows."
  )
  for (field in names(messages)) {
    count <- provenance[[field]]
    if (count == 0L) next
    noun <- if (is.null(population)) " row" else " cohort row"
    verb <- if (count == 1L) " has " else "s have "
    cli::cli_inform(paste0(count, noun, verb, messages[[field]]))
  }
}

.nis_cost_validate_data <- function(data, call) {
  if (!is.data.frame(data)) {
    cli::cli_abort("`data` must be a collected data frame.",
      call = call
    )
  }
}

.nis_cost_validate_charge <- function(charges, call) {
  if (!is.character(charges) || length(charges) != 1L || is.na(charges)) {
    cli::cli_abort("`charges` must be a single column name.",
      call = call
    )
  }
}

.nis_cost_validate_columns <- function(data, charges, call) {
  required <- c("YEAR", charges, "CCR_NIS")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort("`data` is missing required column{?s} {.val {missing}}.",
      call = call
    )
  }
}

.nis_cost_validate_dollars <- function(dollars, call) {
  if (length(dollars) != 1L || !is.numeric(dollars) || !dollars %in% .cpi_u$year) {
    cli::cli_abort("`dollars` must be one year from 2012 through 2024.",
      call = call
    )
  }
}

.nis_cost_validate_numeric <- function(data, charges, call) {
  if (!is.numeric(data$YEAR) || !is.numeric(data[[charges]]) ||
      !is.numeric(data$CCR_NIS)) {
    cli::cli_abort("`YEAR`, {.field {charges}}, and `CCR_NIS` must be numeric.",
      call = call
    )
  }
}

.nis_cost_year_index <- function(year, call) {
  index <- match(year, .cpi_u$year)
  if (anyNA(index)) {
    cli::cli_abort("`YEAR` contains values without a CPI-U index (2012-2024).",
      call = call
    )
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
    charges_treatment = paste0(
      "Negative, missing, or non-finite charges produce NA charges_adj and ",
      "cost_adj; zero charges are retained."
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
#'   `CCR_NIS`. Lazy DuckDB queries must be collected first.
#' @param dollars Reference dollar year, from 2012 through 2024.
#' @param charges Name of the total-charge column. Defaults to `"TOTCHG"`.
#'   Negative, missing, and non-finite values are invalid; zero is retained.
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
  nis_adjust_costs(data, dollars, charges, call = rlang::current_call())
}

nis_adjust_costs <- function(data, dollars, charges, call, population = NULL) {
  .nis_cost_validate_data(data, call)
  .nis_cost_validate_charge(charges, call)
  .nis_cost_validate_columns(data, charges, call)
  .nis_cost_validate_dollars(dollars, call)
  .nis_cost_validate_numeric(data, charges, call)
  index <- .nis_cost_year_index(data$YEAR, call)

  reference_index <- .cpi_u$index[match(as.integer(dollars), .cpi_u$year)]
  ccr <- data$CCR_NIS
  valid_ccr <- dplyr::coalesce(is.finite(ccr) & ccr > 0, FALSE)
  charges_value <- data[[charges]]
  valid_charges <- dplyr::coalesce(is.finite(charges_value) & charges_value >= 0, FALSE)
  reported <- if (is.null(population)) seq_len(nrow(data)) else population
  invalid_ccr_count <- sum(!valid_ccr[reported])
  missing_charges_count <- sum(!valid_charges[reported])
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
  nis_cost_report(provenance, population)
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
#'   year, annual multipliers, counts of invalid CCR and of missing or invalid
#'   charges, and output
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
