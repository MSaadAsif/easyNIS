.nis_cell_count_records <- function(.data) {
  if (inherits(.data, "tbl_svy") && !is.null(.data$variables)) {
    .data <- nis_cohort_records(.data$variables)
  }
  if (!is.data.frame(.data) && !(inherits(.data, "tbl_sql") &&
      inherits(dbplyr::remote_con(.data), "duckdb_connection"))) {
    cli::cli_abort("`.data` must be a record-level data frame, a DuckDB query, or a `nis_design()` result.")
  }
  .data
}

nis_hospital_count_query <- function(data, by) {
  schema <- data |>
    dplyr::ungroup() |>
    dplyr::select(dplyr::all_of(.nis_hospital_fields)) |>
    utils::head(0L) |>
    nis_collect()
  if (!all(vapply(schema, is.numeric, logical(1)))) nis_invalid_hospital_ids()

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
  if (any(counts[[aliases[[3L]]]], na.rm = TRUE)) nis_invalid_hospital_ids()
  counts[[aliases[[3L]]]] <- NULL
  names(counts)[match(aliases[1:2], names(counts))] <- c("n", "hospitals")
  dplyr::arrange(counts, dplyr::across(dplyr::all_of(by)))
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
#' `HOSP_NIS`, matching [nis_design()]. Rows with invalid hospital identity
#' are rejected so counts cannot silently understate disclosure risk. For
#' DuckDB queries, the database counts discharges and hospitals and returns
#' only the grouped summary.
#'
#' @param .data Record-level data frame, lazy DuckDB query, or result of [nis_design()].
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
  if (inherits(.data, "tbl_sql")) return(nis_hospital_count_query(.data, by))
  nis_validate_hospital_ids(.data)
  grouped <- dplyr::group_by(.data, dplyr::across(dplyr::all_of(by)))
  dplyr::summarise(
    grouped,
    n = dplyr::n(),
    hospitals = dplyr::n_distinct(YEAR, HOSP_NIS),
    .groups = "drop"
  )
}
