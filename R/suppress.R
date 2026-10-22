validate_suppress_threshold <- function(threshold, error_call) {
  if (!is_valid_suppress_threshold(threshold)) {
    cli::cli_abort("`threshold` must be one non-negative whole number.", call = error_call)
  }
}

is_valid_suppress_threshold <- function(threshold) {
  is_scalar <- length(threshold) == 1L
  is_numeric <- is.numeric(threshold)
  is_finite_nonnegative <- is_scalar && is_numeric && !is.na(threshold) &&
    is.finite(threshold) && threshold >= 0 &&
    threshold <= .Machine$integer.max
  is_whole <- is_finite_nonnegative && threshold == as.integer(threshold)
  is_whole
}

validate_suppress_dots <- function(dots, error_call) {
  if (length(dots) > 0L) {
    cli::cli_abort("Unused arguments in `...`.", call = error_call)
  }
}

check_suppress_columns <- function(columns, arg, x, error_call) {
  if (is.null(columns)) return(character())
  if (!is.character(columns) || anyNA(columns)) {
    cli::cli_abort(
      "`{arg}` must be a character vector of column names.", call = error_call
    )
  }
  absent <- setdiff(columns, names(x))
  if (length(absent)) {
    cli::cli_abort(
      "Column {.val {absent}} specified in `{arg}` not found in `x`.",
      call = error_call
    )
  }
  columns
}

validate_suppress_counts <- function(counts, arg, error_call) {
  if (!is.numeric(counts)) {
    cli::cli_abort("`{arg}` must refer to a numeric column.", call = error_call)
  }
  invalid <- anyNA(counts) || any(!is.finite(counts)) || any(counts < 0) ||
    any(counts != floor(counts))
  if (invalid) {
    cli::cli_abort(
      "`{arg}` must contain finite, non-negative whole counts without missing values.",
      call = error_call
    )
  }
}

validate_df_suppress_args <- function(
    x, count_col, weighted_cols, by, secondary, hospital_col,
    missing_count_col, error_call) {
  validate_dataframe_count_col(count_col, missing_count_col, error_call)
  validate_secondary_option(secondary, error_call)
  columns <- validate_dataframe_columns(
    x, count_col, weighted_cols, by, hospital_col, error_call
  )
  counts <- validate_df_count_columns(
    x, columns$count_col, columns$hospital_col, error_call
  )
  list(
    count_col = columns$count_col,
    weighted_cols = columns$weighted_cols,
    by = columns$by,
    secondary = secondary,
    hospital_col = columns$hospital_col,
    counts = counts$counts,
    hospital_counts = counts$hospital_counts
  )
}

validate_dataframe_count_col <- function(count_col, missing_count_col, error_call) {
  invalid <- missing_count_col || length(count_col) != 1L ||
    !is.character(count_col) || is.na(count_col) || !nzchar(count_col)
  if (invalid) {
    cli::cli_abort("`count_col` must name the unweighted-count column.", call = error_call)
  }
}

validate_secondary_option <- function(secondary, error_call) {
  invalid <- !is.logical(secondary) || length(secondary) != 1L || is.na(secondary)
  if (invalid) cli::cli_abort("`secondary` must be `TRUE` or `FALSE`.", call = error_call)
}

validate_dataframe_columns <- function(
    x, count_col, weighted_cols, by, hospital_col, error_call) {
  columns <- list(
    count_col = check_suppress_columns(count_col, "count_col", x, error_call),
    weighted_cols = check_suppress_columns(
      weighted_cols, "weighted_cols", x, error_call
    ),
    by = check_suppress_columns(by, "by", x, error_call),
    hospital_col = check_suppress_columns(
      hospital_col, "hospital_col", x, error_call
    )
  )
  if (length(columns$hospital_col) > 1L) {
    cli::cli_abort("`hospital_col` must name one column.", call = error_call)
  }
  columns
}

validate_df_count_columns <- function(x, count_col, hospital_col, error_call) {
  counts <- x[[count_col]]
  validate_suppress_counts(counts, "count_col", error_call)
  hospital_counts <- NULL
  if (length(hospital_col)) {
    hospital_counts <- x[[hospital_col]]
    validate_suppress_counts(hospital_counts, "hospital_col", error_call)
  }
  list(counts = counts, hospital_counts = hospital_counts)
}

complementary_suppress_rows <- function(x, counts, primary, by) {
  secondary_rows <- rep(FALSE, nrow(x))
  if (!any(primary)) return(secondary_rows)
  group_id <- if (length(by) == 0L) {
    rep(1L, nrow(x))
  } else {
    dplyr::group_indices(dplyr::group_by(x, dplyr::across(dplyr::all_of(by))))
  }
  for (group in unique(group_id)) {
    rows <- which(group_id == group)
    masked <- rows[primary[rows]]
    if (length(masked) != 1L || length(rows) < 2L) next
    candidates <- rows[!primary[rows] & !is.na(counts[rows]) &
      is.finite(counts[rows]) & counts[rows] > 0]
    if (length(candidates)) {
      secondary_rows[candidates[[which.min(counts[candidates])]]] <- TRUE
    }
  }
  secondary_rows
}

apply_dataframe_suppression <- function(
    x, columns, count_primary, hospital_primary, secondary_rows, threshold) {
  for (column in columns) {
    values <- as.character(x[[column]])
    values[count_primary] <- paste0("\u2264", threshold)
    values[hospital_primary & !count_primary] <- "<2 hospitals"
    values[secondary_rows] <- "Masked"
    x[[column]] <- values
  }
  x
}

suppress_dataframe <- function(
    x, threshold, count_col, weighted_cols, by, secondary, hospital_col,
    missing_count_col, error_call) {
  args <- validate_df_suppress_args(
    x, count_col, weighted_cols, by, secondary, hospital_col,
    missing_count_col, error_call
  )
  count_primary <- args$counts <= threshold
  hospital_primary <- rep(FALSE, nrow(x))
  if (length(args$hospital_col)) {
    hospital_primary <- args$hospital_counts < 2
  }
  primary <- count_primary | hospital_primary
  secondary_rows <- rep(FALSE, nrow(x))
  if (args$secondary) {
    secondary_rows <- complementary_suppress_rows(x, args$counts, primary, args$by)
  }
  columns <- unique(c(args$count_col, args$weighted_cols, args$hospital_col))
  apply_dataframe_suppression(
    x, columns, count_primary, hospital_primary, secondary_rows, threshold
  )
}

validate_survey_suppress_input <- function(x, error_call) {
  valid <- inherits(x, "tbl_svysummary") && !is.null(x$cards$tbl_svysummary)
  if (!valid) {
    cli::cli_abort(
      "`x` must be a table created by `gtsummary::tbl_svysummary()`.",
      call = error_call
    )
  }
}

validate_survey_suppress_args <- function(
    count_col, weighted_cols, by, hospital_col, secondary,
    missing_count_col, error_call) {
  data_frame_only <- !missing_count_col || !is.null(weighted_cols) ||
    !is.null(by) || !is.null(hospital_col)
  if (data_frame_only) {
    cli::cli_abort(
      "`count_col`, `weighted_cols`, `by`, and `hospital_col` apply only to data frames.",
      call = error_call
    )
  }
  if (!identical(secondary, TRUE)) {
    cli::cli_abort("`secondary` applies only to data frames.", call = error_call)
  }
}

survey_suppress_cards <- function(x) {
  cards <- x$cards$tbl_svysummary
  if (!is.null(x$cards$add_overall)) {
    cards <- dplyr::bind_rows(cards, x$cards$add_overall)
  }
  cards
}

survey_row_spec <- function(body, row, cards, card_variable_level) {
  variable <- body$variable[[row]]
  row_type <- body$row_type[[row]]
  var_type <- body$var_type[[row]]
  if (is.na(variable) || is.na(row_type)) return(NULL)
  if (identical(row_type, "level")) {
    return(survey_level_row_spec(
      body, row, variable, var_type, cards, card_variable_level
    ))
  }
  if (identical(row_type, "missing")) {
    return(survey_missing_row_spec(variable, cards))
  }
  if (identical(row_type, "label")) {
    return(survey_label_row_spec(variable, var_type, cards))
  }
  NULL
}

survey_level_row_spec <- function(
    body, row, variable, var_type, cards, card_variable_level) {
  if (identical(var_type, "continuous2")) {
    return(list(
      variable = variable, context = "missing",
      stat_name = "N_nonmiss_unweighted",
      level_index = rep(TRUE, nrow(cards)), continuous2 = TRUE
    ))
  }
  context <- if (identical(var_type, "dichotomous")) "dichotomous" else "categorical"
  list(
    variable = variable, context = context, stat_name = "n_unweighted",
    level_index = survey_level_index(card_variable_level, body$label[[row]]),
    continuous2 = FALSE
  )
}

survey_missing_row_spec <- function(variable, cards) {
  list(
    variable = variable, context = "missing", stat_name = "N_miss_unweighted",
    level_index = rep(TRUE, nrow(cards)), continuous2 = FALSE
  )
}

survey_label_row_spec <- function(variable, var_type, cards) {
  if (identical(var_type, "continuous")) {
    return(list(
      variable = variable, context = "missing",
      stat_name = "N_nonmiss_unweighted",
      level_index = rep(TRUE, nrow(cards)), continuous2 = FALSE
    ))
  }
  if (identical(var_type, "dichotomous")) {
    return(list(
      variable = variable, context = "dichotomous",
      stat_name = "n_unweighted",
      level_index = rep(TRUE, nrow(cards)), continuous2 = FALSE
    ))
  }
  NULL
}

survey_variable_levels <- function(cards) {
  if ("variable_level" %in% names(cards)) {
    vapply(cards[["variable_level"]], function(value) {
      if (length(value) == 0L) "" else as.character(value[[1L]])
    }, character(1))
  } else {
    rep(NA_character_, nrow(cards))
  }
}

survey_level_index <- function(card_variable_level, level) {
  card_variable_level == level
}

survey_continuous2_blank <- function(cell) {
  length(cell) == 0L || (length(cell) == 1L &&
    (is.na(cell) || (is.character(cell) && !nzchar(trimws(cell)))))
}

survey_card_matches <- function(cards, spec, column) {
  matches <- which(cards$variable == spec$variable &
    cards$context == spec$context & cards$stat_name == spec$stat_name &
    cards$gts_column == column & spec$level_index)
  if (length(matches) == 0L && identical(column, "stat_0") &&
      !spec$continuous2) {
    matches <- which(cards$variable == spec$variable &
      cards$context == spec$context & cards$stat_name == spec$stat_name &
      grepl("^stat_[1-9][0-9]*$", cards$gts_column) & spec$level_index)
  }
  matches
}

survey_continuous2_count <- function(cards, matches, variable, column, error_call) {
  count <- if (length(matches) == 1L) {
    suppressWarnings(as.numeric(unlist(cards$stat[[matches]], use.names = FALSE)))
  } else {
    numeric()
  }
  valid <- length(matches) == 1L && length(count) == 1L &&
    !is.na(count) && is.finite(count)
  if (!valid) {
    cli::cli_abort(paste0(
      "Cannot verify the non-missing count for continuous2 statistic `",
      variable, "` in `", column, "`. Keep exactly one finite ",
      "`N_nonmiss_unweighted` card for that variable and column."
    ), call = error_call)
  }
  count
}

survey_card_count <- function(cards, matches, spec, variable, column, error_call) {
  if (spec$continuous2) {
    return(survey_continuous2_count(cards, matches, variable, column, error_call))
  }
  if (length(matches) == 0L) return(NULL)
  counts <- vapply(matches, function(i) {
    as.numeric(unlist(cards$stat[[i]]))[1L]
  }, numeric(1))
  if (length(counts) == 1L) counts else sum(counts, na.rm = TRUE)
}

survey_cell_suppression <- function(body, cards, row, column, spec, threshold, error_call) {
  cell <- body[[column]][[row]]
  if (spec$continuous2 && survey_continuous2_blank(cell)) {
    return(list(body = body, group_masked = FALSE, overall_masked = FALSE))
  }
  matches <- survey_card_matches(cards, spec, column)
  count <- survey_card_count(cards, matches, spec, spec$variable, column, error_call)
  if (is.null(count) || !is.finite(count) || count > threshold) {
    return(list(body = body, group_masked = FALSE, overall_masked = FALSE))
  }
  body[[column]][[row]] <- paste0("\u2264", threshold)
  if (identical(column, "stat_0")) {
    list(body = body, group_masked = FALSE, overall_masked = TRUE)
  } else {
    list(body = body, group_masked = TRUE, overall_masked = FALSE)
  }
}

suppress_survey_row <- function(
    body, cards, row, spec, stat_columns, threshold, error_call) {
  group_masked <- FALSE
  overall_primary_masked <- FALSE
  for (column in stat_columns) {
    result <- survey_cell_suppression(
      body, cards, row, column, spec, threshold, error_call
    )
    body <- result$body
    group_masked <- group_masked || result$group_masked
    overall_primary_masked <- overall_primary_masked || result$overall_masked
  }
  if (group_masked && "stat_0" %in% stat_columns && !overall_primary_masked) {
    body$stat_0[[row]] <- "Masked"
  }
  body
}

suppress_survey_table <- function(x, threshold, error_call) {
  body <- x$table_body
  cards <- survey_suppress_cards(x)
  card_variable_level <- survey_variable_levels(cards)
  stat_columns <- grep("^stat_[0-9]+$", names(body), value = TRUE)
  for (row in seq_len(nrow(body))) {
    spec <- survey_row_spec(body, row, cards, card_variable_level)
    if (is.null(spec)) next
    body <- suppress_survey_row(
      body, cards, row, spec, stat_columns, threshold, error_call
    )
  }
  x <- gtsummary::modify_table_body(x, function(table_body) body)
  gtsummary::modify_footnote_header(
    x,
    footnote = paste0(
      "Statistics based on unweighted n \u2264", threshold,
      " are marked \u2264", threshold, ".",
      if ("stat_0" %in% stat_columns) {
        paste0(
          " Overall cells in rows with a masked by-group cell are marked ",
          "'Masked' unless their own count is at or below the threshold."
        )
      },
      " Other derivable cells are not masked; review tables for other ",
      "derivable cells before sharing ",
      "under the HCUP Data Use Agreement."
    ),
    columns = gtsummary::all_stat_cols(),
    replace = FALSE,
    text_interpret = "html"
  )
}

#' Suppress small unweighted cells in a survey summary
#'
#' For a `gtsummary::tbl_svysummary()` result, replaces displayed statistics
#' when their corresponding unweighted count is at or below `threshold`. Counts
#' come from the `cards` computed by
#' `gtsummary::tbl_svysummary()`. Continuous2 statistic rows use the
#' non-missing count for their corresponding output column. If that count is
#' absent, ambiguous, or non-finite for a displayed statistic, the function
#' errors; blank statistic cells do not require a count. When a by-group cell
#' is masked, the overall cell (`stat_0`) in the same row is marked `Masked`,
#' unless its own count is at or below the threshold. Other derivable cells
#' still need analyst review before sharing. This route checks discharge counts
#' only; it cannot apply the two-hospital rule. Use `nis_cell_counts()` with the
#' data-frame route to apply both disclosure rules.
#'
#' @param x A `gtsummary::tbl_svysummary()` result, optionally with `add_p()`
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
nis_suppress <- function(x, threshold = 10, ..., count_col, weighted_cols = NULL,
                         by = NULL, secondary = TRUE, hospital_col = NULL) {
  error_call <- rlang::current_call()
  dots <- rlang::dots_list(...)
  validate_suppress_dots(dots, error_call)
  validate_suppress_threshold(threshold, error_call)
  if (is.data.frame(x) && !inherits(x, "tbl_svysummary")) {
    return(suppress_dataframe(
      x, threshold, count_col, weighted_cols, by, secondary, hospital_col,
      missing(count_col), error_call
    ))
  }
  validate_survey_suppress_input(x, error_call)
  validate_survey_suppress_args(
    count_col, weighted_cols, by, hospital_col, secondary, missing(count_col),
    error_call
  )
  cli::cli_inform(
    "`nis_suppress()` on a `tbl_svysummary` checks discharge counts only; it does not apply the two-hospital rule."
  )
  suppress_survey_table(x, threshold, error_call)
}
