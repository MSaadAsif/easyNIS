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
#' still need analyst review before sharing.
#'
#' @param x A `gtsummary::tbl_svysummary()` result, optionally with `add_p()`
#'   or `add_overall()`, or a data frame/tibble.
#' @param threshold Maximum unweighted cell count to suppress.
#' @param ... Reserved for compatibility; unused arguments are errors.
#' @param count_col For data frames, the unweighted-count column name (required).
#' @param weighted_cols For data frames, other columns to mask on primary and
#'   secondary rows.
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
nis_suppress <- function(x, threshold = 10, ..., count_col, weighted_cols = NULL,
                         by = NULL, secondary = TRUE) {
  dots <- rlang::dots_list(...)
  if (length(dots) > 0L) {
    cli::cli_abort("Unused arguments in `...`.")
  }
  if (length(threshold) != 1L || !is.numeric(threshold) || is.na(threshold) ||
      !is.finite(threshold) || threshold < 0 || threshold != as.integer(threshold)) {
    cli::cli_abort("`threshold` must be one non-negative whole number.")
  }

  if (is.data.frame(x) && !inherits(x, "tbl_svysummary")) {
    if (missing(count_col) || length(count_col) != 1L ||
        !is.character(count_col) || is.na(count_col) || !nzchar(count_col)) {
      cli::cli_abort("`count_col` must name the unweighted-count column.")
    }
    if (!is.logical(secondary) || length(secondary) != 1L || is.na(secondary)) {
      cli::cli_abort("`secondary` must be `TRUE` or `FALSE`.")
    }
    check_columns <- function(columns, arg) {
      if (is.null(columns)) return(character())
      if (!is.character(columns) || anyNA(columns)) {
        cli::cli_abort("`{arg}` must be a character vector of column names.")
      }
      absent <- setdiff(columns, names(x))
      if (length(absent)) {
        cli::cli_abort("Column {.val {absent}} specified in `{arg}` not found in `x`.")
      }
      columns
    }
    count_col <- check_columns(count_col, "count_col")
    weighted_cols <- check_columns(weighted_cols, "weighted_cols")
    by <- check_columns(by, "by")
    counts <- x[[count_col]]
    if (!is.numeric(counts)) {
      cli::cli_abort("`count_col` must refer to a numeric column.")
    }

    primary <- !is.na(counts) & is.finite(counts) & counts > 0 & counts <= threshold
    secondary_rows <- rep(FALSE, nrow(x))
    if (secondary && any(primary)) {
      group_id <- if (length(by) == 0L) {
        rep(1L, nrow(x))
      } else {
        key <- x[by]
        # `duplicated.data.frame()` treats matching NA group values as equal.
        first <- !duplicated(key)
        ids <- integer(nrow(x))
        ids[first] <- seq_len(sum(first))
        ids <- cummax(ids)
        ids
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
    }
    columns <- unique(c(count_col, weighted_cols))
    for (column in columns) {
      values <- as.character(x[[column]])
      values[primary] <- paste0("\u2264", threshold)
      values[secondary_rows] <- "Masked"
      x[[column]] <- values
    }
    return(x)
  }

  if (!inherits(x, "tbl_svysummary") || is.null(x$cards$tbl_svysummary)) {
    cli::cli_abort("`x` must be a table created by `gtsummary::tbl_svysummary()`.")
  }
  if (!missing(count_col) || !is.null(weighted_cols) || !is.null(by)) {
    cli::cli_abort("`count_col`, `weighted_cols`, and `by` apply only to data frames.")
  }
  if (!identical(secondary, TRUE)) {
    cli::cli_abort("`secondary` applies only to data frames.")
  }

  body <- x$table_body
  cards <- x$cards$tbl_svysummary
  if (!is.null(x$cards$add_overall)) {
    cards <- dplyr::bind_rows(cards, x$cards$add_overall)
  }
  stat_columns <- grep("^stat_[0-9]+$", names(body), value = TRUE)
  card_variable_level <- if ("variable_level" %in% names(cards)) {
    vapply(cards[["variable_level"]], function(value) {
      if (length(value) == 0L) "" else as.character(value[[1L]])
    }, character(1))
  } else {
    rep(NA_character_, nrow(cards))
  }

  for (row in seq_len(nrow(body))) {
    variable <- body$variable[[row]]
    row_type <- body$row_type[[row]]
    var_type <- body$var_type[[row]]
    if (is.na(variable) || is.na(row_type)) next

    continuous2_stat <- identical(row_type, "level") &&
      identical(var_type, "continuous2")
    if (continuous2_stat) {
      context <- "missing"
      stat_name <- "N_nonmiss_unweighted"
      level_index <- rep(TRUE, nrow(cards))
    } else if (identical(row_type, "level")) {
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

    group_masked <- FALSE
    overall_primary_masked <- FALSE
    for (column in stat_columns) {
      cell <- body[[column]][[row]]
      if (continuous2_stat && (length(cell) == 0L ||
          (length(cell) == 1L && (is.na(cell) ||
            (is.character(cell) && !nzchar(trimws(cell))))))) {
        next
      }
      matches <- which(cards$variable == variable &
        cards$context == context & cards$stat_name == stat_name &
        cards$gts_column == column & level_index)
      if (length(matches) == 0L && identical(column, "stat_0") &&
          !continuous2_stat) {
        matches <- which(cards$variable == variable &
          cards$context == context & cards$stat_name == stat_name &
          grepl("^stat_[1-9][0-9]*$", cards$gts_column) & level_index)
      }
      if (continuous2_stat) {
        count <- if (length(matches) == 1L) {
          suppressWarnings(as.numeric(unlist(
            cards$stat[[matches]], use.names = FALSE
          )))
        } else {
          numeric()
        }
        if (length(matches) != 1L || length(count) != 1L ||
            is.na(count) || !is.finite(count)) {
          cli::cli_abort(paste0(
            "Cannot verify the non-missing count for continuous2 statistic `",
            variable, "` in `", column, "`. Keep exactly one finite ",
            "`N_nonmiss_unweighted` card for that variable and column."
          ))
        }
      } else {
        if (length(matches) == 0L) next
        counts <- vapply(matches, function(i) {
          as.numeric(unlist(cards$stat[[i]]))[1L]
        }, numeric(1))
        count <- if (length(counts) == 1L) counts else sum(counts, na.rm = TRUE)
      }
      if (is.finite(count) && count <= threshold) {
        body[[column]][[row]] <- paste0("\u2264", threshold)
        if (identical(column, "stat_0")) {
          overall_primary_masked <- TRUE
        } else {
          group_masked <- TRUE
        }
      }
    }
    if (group_masked && "stat_0" %in% stat_columns &&
        !overall_primary_masked) {
      body$stat_0[[row]] <- "Masked"
    }
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
