.nis_cell_count_records <- function(.data) {
  if (inherits(.data, "tbl_svy") && !is.null(.data$variables)) {
    .data <- nis_cohort_records(.data$variables)
  }
  if (
    !is.data.frame(.data) &&
      !(inherits(.data, "tbl_sql") &&
        inherits(dbplyr::remote_con(.data), "duckdb_connection"))
  ) {
    cli::cli_abort("`.data` must be a record-level data frame, a DuckDB query, or a `nis_design()` result.")
  }
  .data
}

nis_hospital_count_query <- function(data, by) {
  invalid <- reduce_or(lapply(.nis_hospital_fields, function(field) {
    finite <- nis_is_finite_expr(data, field)
    rlang::expr(!dplyr::coalesce(!!finite & !!rlang::sym(field) > 0, FALSE))
  }))
  keys <- union(by, .nis_hospital_fields)
  aliases <- nis_internal_names(data, keys, c("n", "hospitals", ".nis_invalid_hospital", ".nis_discharges"))
  discharges <- rlang::sym(aliases[[4L]])
  hospital_groups <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(!!discharges := dplyr::n(), .groups = "drop")
  counts <- hospital_groups |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::summarise(
      !!aliases[[1L]] := dplyr::coalesce(sum(!!discharges, na.rm = TRUE), 0L),
      !!aliases[[2L]] := dplyr::n(),
      !!aliases[[3L]] := any(!!invalid, na.rm = TRUE),
      .groups = "drop"
    ) |>
    nis_collect()
  if (any(counts[[aliases[[3L]]]], na.rm = TRUE)) {
    nis_invalid_hospital_ids()
  }
  counts[[aliases[[3L]]]] <- NULL
  names(counts)[match(aliases[1:2], names(counts))] <- c("n", "hospitals")
  dplyr::arrange(counts, dplyr::across(dplyr::all_of(by)))
}

.nis_cell_count_validate_by <- function(by) {
  reserved <- intersect(by, c("n", "hospitals"))
  if (length(reserved)) {
    cli::cli_abort("`by` must not contain reserved summary names: {.val {reserved}}.")
  }
}

#' Count discharges and contributing hospitals by cell
#'
#' Count sampled discharges and distinct hospital-years for each cell.
#' Rows need valid hospital and year identifiers. A DuckDB input returns
#' only grouped counts to R.
#'
#' @param .data Record-level data frame, lazy DuckDB query, or result of [nis_design()].
#' @param by <[tidy-select][dplyr::dplyr_tidy_select]> Cell-defining columns.
#'   Omit or select no columns for overall counts. Use name-based selectors on
#'   DuckDB queries. The summary names `n` and `hospitals` are reserved.
#'
#' @return A data frame with the columns in `by`, `n` (unweighted discharges),
#'   and `hospitals` (distinct year-scoped hospitals).
#' @family disclosure
#' @seealso [Check disclosure before sharing results](https://msaadasif.github.io/easyNIS/articles/disclosure.html),
#'   [Check disclosure before sharing results](https://msaadasif.github.io/easyNIS/articles/disclosure.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(2020))
#' nis_cell_counts(nis, by = DQTR)
nis_cell_counts <- function(.data, by = NULL) {
  .data <- .nis_cell_count_records(.data)
  by <- nis_select_columns(.data, rlang::enquo(by))
  .nis_cell_count_validate_by(by)
  nis_validate_hospital_columns(.data)
  if (inherits(.data, "tbl_sql")) {
    nis_validate_hospital_types(.data)
    return(nis_hospital_count_query(.data, by))
  }
  nis_validate_hospital_ids(.data)
  grouped <- dplyr::group_by(.data, dplyr::across(dplyr::all_of(by)))
  dplyr::summarise(
    grouped,
    n = dplyr::n(),
    hospitals = dplyr::n_distinct(YEAR, HOSP_NIS),
    .groups = "drop"
  )
}
