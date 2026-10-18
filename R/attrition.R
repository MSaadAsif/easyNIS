#' Summarize sequential cohort attrition
#'
#' Applies logical criteria cumulatively and reports remaining and dropped
#' discharge counts at each step. Criteria are evaluated in order; `NA` values
#' are treated as excluded, matching [dplyr::filter()]. The summary is
#' aggregated lazily for Arrow queries and returned as a collected tibble.
#' Missing weights contribute zero to weighted totals.
#'
#' @param .data A data frame or lazy Arrow query.
#' @param ... Named logical expressions applied cumulatively. Unnamed
#'   expressions use their deparsed text as the criterion label.
#' @param by_year If `TRUE`, calculate each step within `YEAR`.
#' @param weight_var Name of the discharge weight column. Defaults to
#'   `"DISCWT"`.
#'
#' @return A tibble with one initial row (`step = 0`) and one row per
#'   criterion. When `by_year = TRUE`, `YEAR` is the first column.
#' @export
#' @examples
#' toy_nis <- tibble::tibble(
#'   AGE = c(16, 45, 60, 72, 55),
#'   ELECTIVE = c(1, 1, 0, 1, 1),
#'   DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
#'   YEAR = rep(2020L, 5)
#' )
#' nis_attrition(toy_nis, adult = AGE >= 18, elective = ELECTIVE == 1)
nis_attrition <- function(.data, ..., by_year = FALSE, weight_var = "DISCWT") {
  criteria <- rlang::enquos(..., .named = TRUE)
  if (length(criteria) == 0L) {
    cli::cli_abort("Supply at least one attrition criterion.")
  }
  if (length(by_year) != 1L || !is.logical(by_year) || is.na(by_year)) {
    cli::cli_abort("`by_year` must be `TRUE` or `FALSE`.")
  }
  if (!is.character(weight_var) || length(weight_var) != 1L ||
      is.na(weight_var) || !nzchar(weight_var)) {
    cli::cli_abort("`weight_var` must be a single column name.")
  }
  absent <- setdiff(c(weight_var, if (by_year) "YEAR"), names(.data))
  if (length(absent) > 0L) {
    cli::cli_abort("`.data` is missing required column{?s} {.val {absent}}.")
  }

  labels <- names(criteria)
  labels[labels == ""] <- vapply(criteria[labels == ""], function(criterion) {
    rlang::as_label(rlang::get_expr(criterion))
  }, character(1))

  keep_names <- paste0(".nis_attrition_keep_", seq_along(criteria))
  while (any(keep_names %in% names(.data))) {
    keep_names <- paste0(".", keep_names)
  }
  keep_exprs <- lapply(seq_along(criteria), function(i) {
    keep <- if (i == 1L) {
      rlang::expr(dplyr::coalesce(!!criteria[[i]], FALSE))
    } else {
      previous <- rlang::sym(keep_names[[i - 1L]])
      rlang::expr((!!previous) & dplyr::coalesce(!!criteria[[i]], FALSE))
    }
    rlang::set_names(list(keep), keep_names[[i]])
  })
  keep_exprs <- unlist(keep_exprs, recursive = FALSE)
  prepared <- dplyr::mutate(.data, !!!keep_exprs)

  summary_exprs <- list()
  summary_exprs[[".nis_attrition_n_0"]] <- rlang::expr(dplyr::n())
  summary_exprs[[".nis_attrition_w_0"]] <- rlang::expr(sum(
    dplyr::coalesce(!!rlang::sym(weight_var), 0)
  ))
  for (i in seq_along(criteria)) {
    keep <- rlang::sym(keep_names[[i]])
    count_name <- paste0(".nis_attrition_n_", i)
    weight_name <- paste0(".nis_attrition_w_", i)
    summary_exprs[[count_name]] <- rlang::expr(sum(dplyr::if_else(!!keep, 1L, 0L)))
    summary_exprs[[weight_name]] <- rlang::expr(sum(dplyr::if_else(
      !!keep, dplyr::coalesce(!!rlang::sym(weight_var), 0), 0
    )))
  }

  grouped <- if (by_year) dplyr::group_by(prepared, YEAR) else prepared
  counts <- dplyr::summarise(grouped, !!!summary_exprs, .groups = "drop") |>
    nis_collect()
  if (by_year && anyNA(counts$YEAR)) {
    cli::cli_abort("`YEAR` must not contain missing values when `by_year` is `TRUE`.")
  }
  if (by_year && nrow(counts) == 0L) {
    return(tibble::tibble(
      YEAR = counts$YEAR,
      step = integer(),
      criterion = character(),
      n_unweighted = integer(),
      n_dropped_unweighted = integer(),
      n_weighted = double(),
      n_dropped_weighted = double(),
      pct_retained = double()
    ))
  }

  groups <- if (by_year) seq_len(nrow(counts)) else 1L
  rows <- lapply(groups, function(group) {
    group_counts <- counts[group, , drop = FALSE]
    n <- vapply(seq_along(criteria), function(i) {
      group_counts[[paste0(".nis_attrition_n_", i)]][[1L]]
    }, numeric(1))
    weighted <- vapply(seq_along(criteria), function(i) {
      group_counts[[paste0(".nis_attrition_w_", i)]][[1L]]
    }, numeric(1))
    n <- c(group_counts[[".nis_attrition_n_0"]][[1L]], n)
    weighted <- c(group_counts[[".nis_attrition_w_0"]][[1L]], weighted)
    dropped <- c(0, n[-length(n)] - n[-1L])
    dropped_weighted <- c(0, weighted[-length(weighted)] - weighted[-1L])
    denominator <- n[[1L]]
    result <- tibble::tibble(
      step = seq.int(0L, length(criteria)),
      criterion = c("All discharges", labels),
      n_unweighted = as.integer(n),
      n_dropped_unweighted = as.integer(dropped),
      n_weighted = weighted,
      n_dropped_weighted = dropped_weighted,
      pct_retained = if (denominator == 0) rep(NA_real_, length(n)) else 100 * n / denominator
    )
    if (by_year) dplyr::mutate(result, YEAR = counts$YEAR[[group]], .before = 1L) else result
  })
  dplyr::bind_rows(rows)
}
