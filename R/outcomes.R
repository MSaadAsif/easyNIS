#' Add standard discharge outcomes
#'
#' Derive in-hospital mortality, length of stay, and discharge disposition
#' from the numeric NIS Core fields. Each outcome uses its own source field.
#' Missing or unrecognized codes become `NA`, including negative HCUP
#' sentinels and non-integer values.
#'
#' @param .data A data frame or lazy DuckDB table with numeric `DIED`, `LOS`,
#'   and `DISPUNIFORM` fields. Apply this before converting the fields to labels.
#'
#' @return The input with three columns added or replaced:
#'   - `in_hospital_death`: 0 for discharge alive and 1 for in-hospital death
#'     from `DIED`.
#'   - `los_days`: elapsed days from `LOS`, including zero for same-day stays.
#'     Values outside the HCUP inpatient range of 0 to 365 whole days become
#'     missing.
#'   - `discharge_disposition`: character labels from `DISPUNIFORM` using
#'     the same labels as [nis_label()]. Codes
#'     1, 2, 5, 6, 7, and 20 distinguish routine home/self-care, short-term
#'     hospital transfer, other facility transfer, home health care, discharge
#'     against medical advice, and in-hospital death. Codes 21 (court/law
#'     enforcement) and 99 (alive, destination unknown) retain their own labels.
#'
#'   For a lazy DuckDB input, the result is a lazy query.
#' @seealso [Hospitalization outcomes](articles/outcomes.html), [nis_cost()]
#' @export
#' @examples
#' nis_open(nis_example(years = 2024)) |>
#'   nis_outcomes() |>
#'   dplyr::count(discharge_disposition) |>
#'   dplyr::collect()
nis_outcomes <- function(.data) {
  required <- c("DIED", "LOS", "DISPUNIFORM")
  missing <- setdiff(required, nis_names(.data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "`.data` is missing required column{?s} {.val {missing}}."
    )
  }
  disposition <- .hcup_labels[.hcup_labels$variable == "DISPUNIFORM" & !is.na(.hcup_labels$code), ]
  disposition_cases <- Map(
    function(code, label) rlang::expr(.data$DISPUNIFORM == !!code ~ !!label),
    disposition$code,
    disposition$value_label
  )

  dplyr::mutate(
    .data,
    in_hospital_death = dplyr::case_when(
      .data$DIED == 0L ~ 0L,
      .data$DIED == 1L ~ 1L
    ),
    los_days = dplyr::case_when(
      dplyr::between(.data$LOS, 0L, 365L) & .data$LOS == floor(.data$LOS) ~ as.double(.data$LOS)
    ),
    discharge_disposition = dplyr::case_when(!!!disposition_cases)
  )
}
