#' Count discharges and contributing hospitals by cell
#'
#' Produces the unweighted discharge and distinct hospital counts used by
#' [nis_suppress()]. Hospital identity is the year-scoped pair `YEAR` and
#' `HOSP_NIS`, matching [nis_design()]. The input can be a record-level data
#' frame or the result of [nis_design()]. Rows with invalid hospital identity
#' are rejected so counts cannot silently understate disclosure risk.
#'
#' @param .data Record-level data frame or result of [nis_design()].
#' @param by Character vector of cell-defining columns.
#'
#' @return A data frame with the columns in `by`, `n` (unweighted discharges),
#'   and `hospitals` (distinct year-scoped hospitals).
#' @export
#' @examples
#' records <- data.frame(
#'   YEAR = c(2020, 2020, 2020), HOSP_NIS = c(1, 1, 2), group = c("A", "A", "A")
#' )
#' nis_cell_counts(records, by = "group")
nis_cell_counts <- function(.data, by) {
  if (inherits(.data, "tbl_svy") && !is.null(.data$variables)) {
    .data <- .data$variables
  }
  if (!is.data.frame(.data)) {
    cli::cli_abort("`.data` must be a record-level data frame or `nis_design()` result.")
  }
  if (!is.character(by) || anyNA(by) || any(!nzchar(by))) {
    cli::cli_abort("`by` must be a character vector of cell-defining columns.")
  }
  required <- c("YEAR", "HOSP_NIS", by)
  absent <- setdiff(required, names(.data))
  if (length(absent)) {
    cli::cli_abort("Column{?s} {.val {absent}} required by `nis_cell_counts()` not found.")
  }
  year <- .data[["YEAR"]]
  hospital <- .data[["HOSP_NIS"]]
  if (!is.numeric(year) || !is.numeric(hospital) || anyNA(year) || anyNA(hospital) ||
      any(!is.finite(year)) || any(!is.finite(hospital)) || any(year <= 0) ||
      any(hospital <= 0)) {
    cli::cli_abort("`YEAR` and `HOSP_NIS` must contain finite positive values.")
  }
  grouped <- if (length(by)) {
    dplyr::group_by(.data, dplyr::across(dplyr::all_of(by)))
  } else {
    dplyr::group_by(.data)
  }
  dplyr::summarise(
    grouped,
    n = dplyr::n(),
    hospitals = dplyr::n_distinct(YEAR, HOSP_NIS),
    .groups = "drop"
  )
}
