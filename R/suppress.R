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
#' For a `gtsummary::tbl_svysummary()` result, replaces displayed statistics
#' when their corresponding unweighted count is at or below `threshold`. The
#' count is the smaller of the summary card count and the number of matching
#' records in the supplied survey design. A dichotomous row whose displayed
#' level passes both rules is marked `Masked` if its non-missing complement
#' fails the count or hospital rule. Continuous2 statistic rows use the
#' non-missing count for their corresponding output column. If that count is
#' absent, ambiguous, or non-finite for a displayed statistic, the function
#' errors; blank statistic cells do not require a count. When a by-group cell
#' is masked, the overall cell (`stat_0`) in the same row is marked `Masked`,
#' unless its own count is at or below the threshold. Other derivable cells
#' still need analyst review before sharing. For survey summaries, hospital
#' support is counted from retained records using year-scoped `YEAR` and
#' `HOSP_NIS` identities, within the cohort, non-missing/category, and by-group
#' cells represented by the table. The rule is applied only when the survey
#' records and summary cards provide an unambiguous mapping; otherwise the
#' function errors. Data-frame behavior uses the supplied `count_col` and
#' optional `hospital_col` as described below.
#'
#' @param .data A `gtsummary::tbl_svysummary()` result, optionally with `add_p()`
#'   or `add_overall()`, or a data frame/tibble.
#' @param threshold Maximum unweighted cell count to suppress.
#' @param ... Reserved for compatibility; unused arguments are errors.
#' @param count_col For data frames, the unweighted-count column name (required).
#' @param weighted_cols For data frames, other columns to mask on primary and
#'   secondary rows.
#' @param hospital_col Optional data-frame column containing the number of
#'   distinct contributing hospitals for each cell. Cells with fewer than two
#'   hospitals are marked `<2 hospitals`. Missing
#'   or invalid hospital counts are errors. Hospital identifiers must be
#'   counted by year; [nis_cell_counts()] computes counts from record-level
#'   data or an `nis_design()` result.
#' @param by Optional data-frame grouping column names defining strata for
#'   complementary suppression.
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
#' @seealso [Disclosure and suppression](articles/disclosure.html).
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
  if (is.data.frame(.data) && !inherits(.data, "tbl_svysummary")) {
    return(suppress_dataframe(
      .data,
      threshold,
      count_col,
      weighted_cols,
      by,
      secondary,
      hospital_col,
      missing(count_col),
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
    missing(count_col),
    error_call
  )
  suppress_survey_table(.data, threshold, error_call)
}
