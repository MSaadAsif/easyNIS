.nis_cell_count_records <- function(.data) {
  if (inherits(.data, "tbl_svy") && !is.null(.data$variables)) {
    .data <- nis_cohort_records(.data$variables)
  }
  if (!is.data.frame(.data)) {
    cli::cli_abort("`.data` must be a record-level data frame or `nis_design()` result.")
  }
  .data
}

.nis_cell_count_validate_by <- function(by) {
  if (!is.character(by) || anyNA(by) || any(!nzchar(by))) {
    cli::cli_abort("`by` must be a character vector of cell-defining columns.")
  }
  reserved <- intersect(by, c("n", "hospitals"))
  if (length(reserved)) {
    cli::cli_abort("`by` must not contain reserved summary names: {.val {reserved}}.")
  }
}

#' Count discharges and contributing hospitals by cell
#'
#' Produces the unweighted discharge and distinct hospital counts used by
#' [nis_suppress()]. Hospital identity is the year-scoped pair `YEAR` and
#' `HOSP_NIS`, matching [nis_design()]. The input can be a record-level data
#' frame or the result of [nis_design()]. Rows with invalid hospital identity
#' are rejected so counts cannot silently understate disclosure risk.
#'
#' @param .data Record-level data frame or result of [nis_design()].
#' @param by Character vector of cell-defining columns. The summary names `n`
#'   and `hospitals` are reserved and cannot be used as cell-defining columns.
#'
#' @return A data frame with the columns in `by`, `n` (unweighted discharges),
#'   and `hospitals` (distinct year-scoped hospitals).
#' @family disclosure
#' @seealso [Disclosure and suppression](articles/disclosure.html).
#' @export
#' @examples
#' records <- data.frame(
#'   YEAR = c(2020, 2020, 2020), HOSP_NIS = c(1, 1, 2), group = c("A", "A", "A")
#' )
#' nis_cell_counts(records, by = "group")
nis_cell_counts <- function(.data, by) {
  .data <- .nis_cell_count_records(.data)
  .nis_cell_count_validate_by(by)
  nis_validate_hospital_columns(.data, by)
  nis_validate_hospital_ids(.data)
  grouped <- dplyr::group_by(.data, dplyr::across(dplyr::all_of(by)))
  dplyr::summarise(
    grouped,
    n = dplyr::n(),
    hospitals = dplyr::n_distinct(YEAR, HOSP_NIS),
    .groups = "drop"
  )
}
