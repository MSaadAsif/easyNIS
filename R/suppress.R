validate_suppress_threshold <- function(threshold, error_call) {
  if (!nis_is_nonnegative_integer(threshold)) {
    cli::cli_abort("`threshold` must be one non-negative whole number.", call = error_call)
  }
}

validate_suppress_dots <- function(dots, error_call) {
  if (length(dots) > 0L) {
    cli::cli_abort("Unused arguments in `...`.", call = error_call)
  }
}

#' Suppress small unweighted cells in a survey summary
#'
#' Mask a summary using unweighted counts and contributing hospitals.
#'
#' @details In a survey table, each statistic is checked against its
#' supporting discharges and hospital-years. The function stops when it
#' cannot identify the records behind a statistic. It also checks the
#' non-missing complement of a displayed two-level indicator and can mask
#' related overall statistics. If one categorical level in a column is
#' masked, the function also masks the smallest remaining positive level.
#' Review other deductions from related outputs before release.
#'
#' In a data frame, supply unweighted counts and, when available, distinct
#' hospital counts. Grouped complementary suppression can mask an additional
#' positive cell when there is one primary mask in a group. Review totals
#' and any other cells that someone could recover by subtraction.
#'
#' @param .data A `gtsummary::tbl_svysummary()` result, optionally with `add_p()`
#'   or `add_overall()`, or a data frame/tibble.
#' @param threshold Maximum unweighted cell count to suppress.
#' @param ... Reserved for compatibility; unused arguments are errors.
#' @param count_col <[tidy-select][dplyr::dplyr_tidy_select]> For data frames,
#'   select exactly one unweighted-count column.
#' @param weighted_cols <[tidy-select][dplyr::dplyr_tidy_select]> For data
#'   frames, other columns to mask on primary and secondary rows.
#' @param hospital_col <[tidy-select][dplyr::dplyr_tidy_select]> Optional
#'   selection of a single data-frame column containing the number of
#'   distinct contributing hospitals for each cell. Cells with fewer than two
#'   hospitals are marked `<2 hospitals`. Missing
#'   or invalid hospital counts are errors. Hospital identifiers must be
#'   counted by year; [nis_cell_counts()] computes counts from record-level
#'   data or an `nis_design()` result.
#' @param by <[tidy-select][dplyr::dplyr_tidy_select]> Optional data-frame
#'   grouping columns defining strata for complementary suppression.
#' @param secondary Apply complementary suppression. For data frames this masks
#'   the smallest remaining positive count when exactly one row in a stratum is
#'   primary-masked. This is single-dimension complementary suppression, not a
#'   full cell-suppression solver; totals rows must be handled or excluded by
#'   the user.
#'
#' @return For data frames, the same table with masked columns converted to
#'   character. For `gtsummary` results, the table with primary and secondary
#'   masks and a footnote describing them.
#' @family disclosure
#' @seealso [Check disclosure before sharing results](https://msaadasif.github.io/easyNIS/articles/disclosure.html),
#'   [Check disclosure before sharing results](https://msaadasif.github.io/easyNIS/articles/disclosure.html).
#' @export
#' @examplesIf rlang::is_installed(c("gtsummary", "cardx", "survey"))
#' nis <- nis_open(nis_example(years = 2019:2020)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
#' table <- gtsummary::tbl_svysummary(
#'   design,
#'   by = RACE,
#'   include = c(AGE, FEMALE)
#' )
#' nis_suppress(table, threshold = 10)
#' @examples
#' nis <- nis_open(nis_example(2020))
#' cells <- nis_cell_counts(nis, by = DQTR)
#' nis_suppress(cells, count_col = n, hospital_col = hospitals, by = DQTR)
nis_suppress <- function(
  .data,
  threshold = 10,
  ...,
  count_col,
  weighted_cols = NULL,
  by = NULL,
  secondary = TRUE,
  hospital_col = NULL
) {
  error_call <- rlang::current_call()
  dots <- rlang::dots_list(...)
  validate_suppress_dots(dots, error_call)
  validate_suppress_threshold(threshold, error_call)
  count_col <- rlang::enquo(count_col)
  weighted_cols <- rlang::enquo(weighted_cols)
  by <- rlang::enquo(by)
  hospital_col <- rlang::enquo(hospital_col)
  if (is.data.frame(.data) && !inherits(.data, "tbl_svysummary")) {
    count_col <- nis_select_columns(.data, count_col, error_call)
    hospital_col <- nis_select_columns(.data, hospital_col, error_call)
    validate_dataframe_count_columns(count_col, hospital_col, error_call)
    weighted_cols <- nis_select_columns(.data, weighted_cols, error_call)
    by <- nis_select_columns(.data, by, error_call)
    return(suppress_dataframe(
      .data,
      threshold,
      count_col,
      weighted_cols,
      by,
      secondary,
      hospital_col,
      error_call
    ))
  }
  validate_survey_suppress_input(.data, error_call)
  validate_survey_suppress_args(
    count_col,
    weighted_cols,
    by,
    hospital_col,
    secondary,
    error_call
  )
  suppress_survey_table(.data, threshold, error_call)
}
