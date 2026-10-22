.nis_cell_count_records <- function(.data) {
  if (inherits(.data, "tbl_svy") && !is.null(.data$variables)) {
    .data <- .data$variables
    if (".in_cohort" %in% nis_names(.data)) { # nolint: object_usage_linter
      .data <- dplyr::filter(.data, .in_cohort)
    }
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
}

.nis_cell_count_validate_cols <- function(.data, by) {
  required <- c("YEAR", "HOSP_NIS", by)
  absent <- setdiff(required, nis_names(.data)) # nolint: object_usage_linter
  if (length(absent)) {
    cli::cli_abort("Column{?s} {.val {absent}} required by `nis_cell_counts()` not found.")
  }
}

.nis_cell_count_valid_id <- function(value) {
  is.numeric(value) && !anyNA(value) && all(is.finite(value)) && all(value > 0)
}

.nis_cell_count_validate_ids <- function(.data) {
  year <- .data[["YEAR"]]
  hospital <- .data[["HOSP_NIS"]]
  if (!.nis_cell_count_valid_id(year) || !.nis_cell_count_valid_id(hospital)) {
    cli::cli_abort("`YEAR` and `HOSP_NIS` must contain finite positive values.")
  }
}

.nis_cell_count_group <- function(.data, by) {
  if (length(by)) {
    dplyr::group_by(.data, dplyr::across(dplyr::all_of(by)))
  } else {
    dplyr::group_by(.data)
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
#' @param by Character vector of cell-defining columns.
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
  .nis_cell_count_validate_cols(.data, by)
  .nis_cell_count_validate_ids(.data)
  grouped <- .nis_cell_count_group(.data, by)
  dplyr::summarise(
    grouped,
    n = dplyr::n(),
    hospitals = dplyr::n_distinct(YEAR, HOSP_NIS),
    .groups = "drop"
  )
}
