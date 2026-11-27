#' Add standard discharge outcomes
#'
#' Derive in-hospital death, length of stay, and discharge disposition.
#'
#' @details In-hospital death uses `DIED`. Discharge disposition uses
#' `DISPUNIFORM`. Length of stay uses `LOS`, including zero for same-day
#' stays. Missing values, HCUP sentinel values, and invalid codes produce
#' missing outcomes.
#'
#' @param .data A data frame or lazy DuckDB table with numeric `LOS` and
#'   `DISPUNIFORM` fields and numeric or logical `DIED`. Apply this before
#'   labelling disposition.
#'
#' @return The input with three columns added or replaced:
#'   - `in_hospital_death`: `FALSE` for discharge alive and `TRUE` for in-hospital death
#'     from `DIED`.
#'   - `los_days`: elapsed days from `LOS`, including zero for same-day stays.
#'     Values outside the HCUP inpatient range of 0 to 365 whole days become
#'     missing.
#'   - `discharge_disposition`: numeric codes from `DISPUNIFORM`. Use [nis_label()]
#'     after collecting or [nis_design()] to attach factor labels. Codes
#'     1, 2, 5, 6, 7, and 20 distinguish routine home/self-care, short-term
#'     hospital transfer, other facility transfer, home health care, discharge
#'     against medical advice, and in-hospital death. Codes 21 (court/law
#'     enforcement) and 99 (alive, destination unknown) are valid codes.
#'
#'   For a lazy DuckDB input, the result is a lazy query.
#' @seealso [Derive outcomes, comorbidities, and costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html),
#'   [Derive outcomes, comorbidities, and costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html), [nis_cost()]
#' @export
#' @examples
#' nis_open(nis_example(years = 2024)) |>
#'   nis_outcomes() |>
#'   dplyr::count(discharge_disposition) |>
#'   dplyr::collect() |>
#'   nis_label()
nis_outcomes <- function(.data) {
  required <- c("DIED", "LOS", "DISPUNIFORM")
  missing <- setdiff(required, nis_names(.data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "`.data` is missing required column{?s} {.val {missing}}."
    )
  }
  disposition_codes <- .hcup_labels$code[.hcup_labels$variable == "DISPUNIFORM"]

  dplyr::mutate(
    .data,
    in_hospital_death = dplyr::case_when(
      .data$DIED == 0L ~ FALSE,
      .data$DIED == 1L ~ TRUE
    ),
    los_days = dplyr::case_when(
      dplyr::between(.data$LOS, 0L, 365L) & .data$LOS == floor(.data$LOS) ~ as.double(.data$LOS)
    ),
    discharge_disposition = dplyr::case_when(
      .data$DISPUNIFORM %in% disposition_codes ~ .data$DISPUNIFORM
    )
  )
}
