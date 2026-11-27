.nis_attrition_validate_year <- function(by_year) {
  if (length(by_year) != 1L || !is.logical(by_year) || is.na(by_year)) {
    cli::cli_abort("`by_year` must be `TRUE` or `FALSE`.")
  }
}

.nis_attrition_validate_weight <- function(weight_var) {
  if (!is.character(weight_var) || length(weight_var) != 1L || is.na(weight_var) || !nzchar(weight_var)) {
    cli::cli_abort("`weight_var` must be a single column name.")
  }
}

.nis_attrition_validate_cols <- function(.data, by_year, weight_var) {
  absent <- setdiff(c(weight_var, if (by_year) "YEAR"), nis_names(.data))
  if (length(absent) > 0L) {
    cli::cli_abort("`.data` is missing required column{?s} {.val {absent}}.")
  }
}

.nis_attrition_validate <- function(.data, by_year, weight_var) {
  .nis_attrition_validate_year(by_year)
  .nis_attrition_validate_weight(weight_var)
  .nis_attrition_validate_cols(.data, by_year, weight_var)
}

.nis_attrition_keep_names <- function(.data, criteria_count) {
  nis_internal_names(.data, nis_names(.data), paste0(".nis_attrition_keep_", seq_len(criteria_count)))
}

.nis_attrition_keep_exprs <- function(criteria, keep_names) {
  keep_exprs <- lapply(seq_along(criteria), function(i) {
    keep <- if (i == 1L) {
      rlang::expr(dplyr::coalesce(!!criteria[[i]], FALSE))
    } else {
      previous <- rlang::sym(keep_names[[i - 1L]])
      rlang::expr((!!previous) & dplyr::coalesce(!!criteria[[i]], FALSE))
    }
    rlang::set_names(list(keep), keep_names[[i]])
  })
  unlist(keep_exprs, recursive = FALSE)
}

nis_attrition_metrics <- function(data, criteria_count) {
  steps <- seq.int(0L, criteria_count)
  aliases <- nis_internal_names(
    data,
    nis_names(data),
    c(paste0(".nis_attrition_n_", steps), paste0(".nis_attrition_w_", steps))
  )
  positions <- seq_along(steps)
  list(n = aliases[positions], weight = aliases[length(steps) + positions])
}

.nis_attrition_summary_exprs <- function(metrics, keep_names, weight) {
  summary_exprs <- list()
  summary_exprs[[metrics$n[[1L]]]] <- rlang::expr(dplyr::n())
  summary_exprs[[metrics$weight[[1L]]]] <- rlang::expr(sum(!!weight, na.rm = TRUE))
  for (i in seq_along(keep_names)) {
    keep <- rlang::sym(keep_names[[i]])
    summary_exprs[[metrics$n[[i + 1L]]]] <- rlang::expr(sum(
      dplyr::if_else(!!keep, 1L, 0L),
      na.rm = TRUE
    ))
    summary_exprs[[metrics$weight[[i + 1L]]]] <- rlang::expr(sum(
      dplyr::if_else(
        !!keep,
        !!weight,
        0
      ),
      na.rm = TRUE
    ))
  }
  summary_exprs
}

.nis_attrition_summarise <- function(.data, summary_exprs, by_year, baseline) {
  grouped <- if (by_year) dplyr::group_by(.data, YEAR) else .data
  counts <- dplyr::summarise(grouped, !!!summary_exprs, .groups = "drop") |>
    nis_collect()
  # SQL SUM returns NULL on empty inputs; R sum returns zero.
  counts[counts[[baseline]] == 0, names(summary_exprs)] <- 0
  counts
}

.nis_attrition_rows <- function(counts, labels, by_year, metrics) {
  steps <- seq_along(labels) - 1L
  rows <- rep(seq_len(nrow(counts)), each = length(steps))
  step <- rep(steps, times = nrow(counts))
  gather <- function(columns) {
    metrics <- lapply(counts[columns], as.numeric)
    as.numeric(t(do.call(cbind, metrics)))
  }
  n <- gather(metrics$n)
  weight <- gather(metrics$weight)
  previous <- seq_along(step) - 1L
  previous[step == 0L] <- NA_integer_
  denominator <- as.numeric(counts[[metrics$n[[1L]]]])[rows]
  result <- dplyr::tibble(
    step = step,
    criterion = labels[step + 1L],
    n_unweighted = as.integer(n),
    n_dropped_unweighted = as.integer(n[previous] - n),
    n_weighted = weight,
    n_dropped_weighted = weight[previous] - weight,
    pct_retained = dplyr::if_else(denominator == 0, NA_real_, 100 * n / denominator)
  )
  if (by_year) dplyr::mutate(result, YEAR = counts$YEAR[rows], .before = 1L) else result
}

.nis_attrition_design_sample <- function(.data) {
  absent <- setdiff(.nis_design_fields, nis_names(.data))
  if (length(absent) > 0L) {
    cli::cli_abort("`.data` is missing design column{?s} {.val {absent}}.")
  }
  any_invalid <- reduce_or(nis_design_invalid_exprs(.data))
  dplyr::filter(.data, !(!!any_invalid))
}

#' Summarize sequential cohort attrition
#'
#' Applies logical criteria cumulatively and reports remaining and dropped
#' discharge counts at each step. The initial row has no preceding step, so its
#' dropped counts are `NA`. Criteria are evaluated in order; `NA` values
#' are treated as excluded, matching [dplyr::filter()]. The summary is
#' aggregated lazily for DuckDB queries and returned as a collected tibble.
#' Missing weights (including `NaN`) contribute zero to weighted totals.
#' Existing input groups are ignored, including when evaluating criteria.
#' Criteria are evaluated over the full input before annual aggregation.
#'
#' @template dot-data
#' @param ... Named logical expressions applied cumulatively. Unnamed
#'   expressions use their deparsed text as the criterion label.
#' @param by_year If `TRUE`, calculate each step within `YEAR`.
#' @param weight_var Name of the discharge weight column. Defaults to
#'   `"DISCWT"`.
#' @param .design If `TRUE`, count only discharges with valid survey design
#'   fields, using the policy in [nis_design()]. Criteria still evaluate over
#'   the full ungrouped input. Use `cohort = !!nis_attrition_cohort(flow)` with
#'   the same input to build the survey design from the rules in `flow`. Use
#'   deterministic criteria, since they are evaluated by both functions.
#' @param flow Result from `nis_attrition(..., .design = TRUE)`.
#'
#' @return `nis_attrition()` returns a tibble with one initial row (`step = 0`)
#'   and one row per criterion. When `by_year = TRUE`, `YEAR` is the first
#'   column. With `.design = TRUE`, the initial row counts valid design
#'   discharges and the tibble stores the combined cohort expression.
#'   `nis_attrition_cohort()` extracts that expression for injection with `!!`
#'   into `cohort` in [nis_design()].
#' @family cohort-definition
#' @seealso [Defining cohorts](articles/cohorts.html).
#' @export
#' @examples
#' toy_nis <- dplyr::tibble(
#'   AGE = c(16, 45, 60, 72, 55),
#'   ELECTIVE = c(1, 1, 0, 1, 1),
#'   DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
#'   HOSP_NIS = c(1L, 1L, 2L, 2L, 2L),
#'   NIS_STRATUM = rep(1L, 5),
#'   YEAR = rep(2020L, 5)
#' )
#' nis_attrition(toy_nis, adult = AGE >= 18, elective = ELECTIVE == 1)
#' flow <- nis_attrition(toy_nis, adult = AGE >= 18, .design = TRUE)
#' nis_attrition_cohort(flow)
nis_attrition <- function(.data, ..., by_year = FALSE, weight_var = "DISCWT", .design = FALSE) {
  criteria <- rlang::enquos(..., .named = TRUE)
  if (length(criteria) == 0L) {
    cli::cli_abort("Supply at least one attrition criterion.")
  }
  .nis_attrition_validate(.data, by_year, weight_var)
  if (!rlang::is_bool(.design)) {
    cli::cli_abort("`.design` must be `TRUE` or `FALSE`.")
  }
  keep_names <- .nis_attrition_keep_names(.data, length(criteria))
  keep_exprs <- .nis_attrition_keep_exprs(criteria, keep_names)
  prepared <- dplyr::mutate(dplyr::ungroup(.data), !!!keep_exprs)
  if (.design) {
    prepared <- .nis_attrition_design_sample(prepared)
  }
  missing_weight <- nis_is_missing_expr(prepared, weight_var)
  weight <- rlang::expr(dplyr::if_else(
    !!missing_weight,
    0,
    as.double(!!rlang::sym(weight_var))
  ))
  metrics <- nis_attrition_metrics(prepared, length(criteria))
  summary_exprs <- .nis_attrition_summary_exprs(metrics, keep_names, weight)
  counts <- .nis_attrition_summarise(prepared, summary_exprs, by_year, metrics$n[[1L]])
  if (by_year && anyNA(counts$YEAR)) {
    cli::cli_abort("`YEAR` must not contain missing values when `by_year` is `TRUE`.")
  }
  baseline <- if (.design) "Valid design discharges" else "All discharges"
  result <- .nis_attrition_rows(counts, c(baseline, names(criteria)), by_year, metrics)
  if (.design) {
    attr(result, "nis_cohort") <- Reduce(function(left, right) rlang::expr((!!left) & (!!right)), criteria)
  }
  result
}

#' @rdname nis_attrition
#' @export
nis_attrition_cohort <- function(flow) {
  cohort <- attr(flow, "nis_cohort", exact = TRUE)
  if (is.null(cohort)) {
    cli::cli_abort("Pass the result of `nis_attrition(..., .design = TRUE)`.")
  }
  cohort
}
