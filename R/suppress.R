#' Suppress small unweighted cells in a survey summary
#'
#' Replaces displayed statistics when their corresponding unweighted count is
#' at or below `threshold`. Counts come from the `cards` computed by
#' `gtsummary::tbl_svysummary()`. This masks primary cells only; it does not
#' perform complementary suppression, so related totals may still reveal a
#' masked count.
#'
#' @param x A `gtsummary::tbl_svysummary()` result, optionally with `add_p()`.
#' @param threshold Maximum unweighted cell count to suppress.
#'
#' @return The table with small statistics masked and a HCUP DUA footnote.
#' @export
#' @examples
#' if (rlang::is_installed(c("gtsummary", "cardx", "survey"))) {
#'   nis <- nis_open(nis_example(years = 2019:2020)) |>
#'     nis_flag_dx(heart_failure = "I50")
#'   design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
#'   table <- gtsummary::tbl_svysummary(
#'     design,
#'     by = RACE,
#'     include = c(AGE, FEMALE)
#'   )
#'   nis_suppress(table, threshold = 10)
#' }
nis_suppress <- function(x, threshold = 10) {
  if (!inherits(x, "tbl_svysummary") || is.null(x$cards$tbl_svysummary)) {
    cli::cli_abort("`x` must be a table created by `gtsummary::tbl_svysummary()`.")
  }
  if (length(threshold) != 1L || !is.numeric(threshold) || is.na(threshold) ||
      !is.finite(threshold) || threshold < 0 || threshold != as.integer(threshold)) {
    cli::cli_abort("`threshold` must be one non-negative whole number.")
  }

  body <- x$table_body
  cards <- x$cards$tbl_svysummary
  if (!is.null(x$cards$add_overall)) {
    cards <- dplyr::bind_rows(cards, x$cards$add_overall)
  }
  stat_columns <- grep("^stat_[0-9]+$", names(body), value = TRUE)
  card_variable_level <- vapply(cards$variable_level, function(value) {
    if (length(value) == 0L) "" else as.character(value[[1L]])
  }, character(1))

  for (row in seq_len(nrow(body))) {
    variable <- body$variable[[row]]
    row_type <- body$row_type[[row]]
    var_type <- body$var_type[[row]]
    if (is.na(variable) || is.na(row_type)) next

    if (identical(row_type, "level")) {
      context <- if (identical(var_type, "dichotomous")) "dichotomous" else "categorical"
      stat_name <- "n_unweighted"
      level <- body$label[[row]]
      level_index <- card_variable_level == level
    } else if (identical(row_type, "missing")) {
      context <- "missing"
      stat_name <- "N_miss_unweighted"
      level_index <- rep(TRUE, nrow(cards))
    } else if (identical(row_type, "label") && identical(var_type, "continuous")) {
      context <- "missing"
      stat_name <- "N_nonmiss_unweighted"
      level_index <- rep(TRUE, nrow(cards))
    } else if (identical(row_type, "label") && identical(var_type, "dichotomous")) {
      context <- "dichotomous"
      stat_name <- "n_unweighted"
      level_index <- rep(TRUE, nrow(cards))
    } else {
      next
    }

    for (column in stat_columns) {
      matches <- which(cards$variable == variable &
        cards$context == context & cards$stat_name == stat_name &
        cards$gts_column == column & level_index)
      if (length(matches) == 0L && identical(column, "stat_0")) {
        matches <- which(cards$variable == variable &
          cards$context == context & cards$stat_name == stat_name &
          grepl("^stat_[1-9][0-9]*$", cards$gts_column) & level_index)
      }
      if (length(matches) == 0L) next
      counts <- vapply(matches, function(i) as.numeric(unlist(cards$stat[[i]]))[1L],
        numeric(1))
      count <- if (length(counts) == 1L) counts else sum(counts, na.rm = TRUE)
      if (is.finite(count) && count <= threshold) {
        body[[column]][[row]] <- paste0("\u2264", threshold)
      }
    }
  }

  x <- gtsummary::modify_table_body(x, function(table_body) body)
  gtsummary::modify_footnote_header(
    x,
    footnote = paste0(
      "Suppressed at unweighted n \u2264 ", threshold,
      " under the HCUP Data Use Agreement small-cell rule."
    ),
    columns = gtsummary::all_stat_cols(),
    replace = FALSE,
    text_interpret = "html"
  )
}
