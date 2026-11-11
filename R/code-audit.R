utils::globalVariables(".nis_invalid_weight")

.nis_audit_is_column_name <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

.nis_audit_summary_names <- c("code_group", "n_cohort_unweighted", "n_unweighted",
  "n_weighted", "pct_within_year", "yoy_pct_change")
.nis_audit_inventory_names <- c("code_group", "code", "n_cohort_unweighted",
  "n_unweighted", "n_weighted", "status")

.nis_audit_valid_by <- function(by) {
  is.character(by) && length(by) > 0L && !anyNA(by) && all(nzchar(by)) &&
    !anyDuplicated(by)
}

.nis_audit_validate_by <- function(.data, by, output) {
  if (!.nis_audit_valid_by(by) || !all(by %in% nis_names(.data))) { # nolint: object_usage_linter
    cli::cli_abort("`by` must name one or more unique existing columns.")
  }
  reserved <- if (output == "inventory") .nis_audit_inventory_names else .nis_audit_summary_names
  if (any(by %in% reserved)) {
    cli::cli_abort("`by` must not have the same name as a summary column.")
  }
}

.nis_audit_validate_sparse_n <- function(sparse_n) {
  if (!is_valid_suppress_threshold(sparse_n)) { # nolint: object_usage_linter
    cli::cli_abort("`sparse_n` must be one non-negative whole number.")
  }
}

.nis_audit_validate_weight <- function(.data, weight_var) {
  if (!.nis_audit_is_column_name(weight_var) ||
      !weight_var %in% nis_names(.data)) { # nolint: object_usage_linter
    cli::cli_abort("`weight_var` must be the name of one existing column.")
  }
}

.nis_audit_check_weight_values <- function(.data, weight_var) {
  weight <- rlang::sym(weight_var)
  weight_column <- dplyr::collect(dplyr::filter(
    dplyr::select(.data, !!weight), !!weight != !!weight
  ))[[weight_var]]
  if (!is.numeric(weight_column)) {
    cli::cli_abort("`weight_var` must be a numeric column.")
  }
  invalid <- dplyr::summarise(dplyr::ungroup(.data), .nis_invalid_weight = dplyr::coalesce(sum(
    as.integer(is.na(!!weight) | !is.finite(!!weight)), na.rm = TRUE
  ), 0L))
  invalid_count <- dplyr::pull(nis_collect(invalid), ".nis_invalid_weight")
  if (invalid_count > 0) {
    cli::cli_abort("`weight_var` must contain only finite, non-missing numeric values in the selected cohort.")
  }
}

.nis_audit_valid_group_names <- function(codes) {
  code_names <- names(codes)
  !is.null(code_names) && !anyNA(code_names) && all(nzchar(code_names)) &&
    !anyDuplicated(code_names)
}

.nis_audit_has_valid_prefixes <- function(prefixes) {
  is.character(prefixes) && length(prefixes) > 0L && !anyNA(prefixes)
}

.nis_audit_validate_codes <- function(codes) {
  valid_type <- is.character(codes) || is.list(codes)
  if (!valid_type || length(codes) == 0L || !.nis_audit_valid_group_names(codes)) {
    cli::cli_abort("`codes` must be a non-empty named vector or list with unique, non-empty names.")
  }
  valid_prefixes <- vapply(codes, .nis_audit_has_valid_prefixes, logical(1))
  if (!all(valid_prefixes)) {
    cli::cli_abort("Each code group must contain non-missing character prefixes.")
  }
  lapply(as.list(codes), identity)
}

.nis_audit_filter_cohort <- function(data, cohort_quo, by) {
  if (rlang::quo_is_null(cohort_quo)) return(data)
  cohort_expression <- rlang::quo_get_expr(cohort_quo)
  literal_empty <- is.logical(cohort_expression) && length(cohort_expression) == 1L &&
    (is.na(cohort_expression) || identical(cohort_expression, FALSE))
  if (literal_empty) {
    period <- rlang::sym(by[[1L]])
    # DuckDB requires a column expression; it rejects literal FALSE/NA filters.
    return(dplyr::filter(data, !is.na(!!period) & !!period != !!period))
  }
  dplyr::filter(data, !!cohort_quo)
}

.nis_audit_temporary_names <- function(input_names, code_count) {
  candidates <- c(
    paste0(".nis_audit_flag_", seq_len(code_count)),
    ".nis_audit_cohort",
    paste0(".nis_audit_n_", seq_len(code_count)),
    paste0(".nis_audit_w_", seq_len(code_count))
  )
  make.unique(c(input_names, candidates), sep = "_")[-seq_along(input_names)]
}

.nis_audit_summary_expressions <- function(flag_names, count_names, weight_names,
                                           weight_var, cohort_count_name) {
  expressions <- list()
  expressions[[cohort_count_name]] <- rlang::expr(dplyr::n())
  for (i in seq_along(flag_names)) {
    flag <- rlang::sym(flag_names[[i]])
    expressions[[count_names[[i]]]] <- rlang::expr(sum(as.integer(!!flag), na.rm = TRUE))
    expressions[[weight_names[[i]]]] <- rlang::expr(sum(
      dplyr::if_else(!!flag, !!rlang::sym(weight_var), 0), na.rm = TRUE
    ))
  }
  expressions
}

.nis_audit_names <- function(input_names, code_count) {
  temp <- .nis_audit_temporary_names(input_names, code_count)
  index <- seq_len(code_count)
  list(
    flag = temp[index],
    cohort = temp[[code_count + 1L]],
    count = temp[code_count + 1L + index],
    weight = temp[2L * code_count + 1L + index]
  )
}

.nis_audit_empty_output <- function(by, summary, output) {
  columns <- if (output == "inventory") {
    dplyr::tibble(
      code_group = character(), code = character(),
      n_cohort_unweighted = integer(), n_unweighted = integer(),
      n_weighted = double(), status = character()
    )
  } else {
    dplyr::tibble(
      code_group = character(), n_cohort_unweighted = integer(),
      n_unweighted = integer(), n_weighted = double(),
      pct_within_year = double(), yoy_pct_change = double()
    )
  }
  columns[by] <- summary[by]
  dplyr::select(columns, dplyr::all_of(by), dplyr::everything())
}

# Periods with a missing component sort after every complete period so they
# never become the "previous" period of a complete one.
.nis_audit_order_periods <- function(summary, by) {
  complete <- stats::complete.cases(summary[by])
  keys <- c(list(!complete), unname(as.list(summary[by])))
  summary[do.call(order, keys), , drop = FALSE]
}

.nis_audit_period_summary <- function(data, expressions, by) {
  summary <- data |>
    dplyr::ungroup() |>
    dplyr::group_by(!!!rlang::syms(by)) |>
    dplyr::summarise(!!!expressions, .groups = "drop") |>
    nis_collect()
  if (nrow(summary) == 0L) return(summary)
  .nis_audit_order_periods(summary, by)
}

# Several `by` columns give no unambiguous year comparison: adjacent rows can be
# quarters of one year or the boundary between two other components.
.nis_audit_yoy_change <- function(pct, summary, by) {
  change <- rep(NA_real_, length(pct))
  if (length(by) > 1L) return(change)
  previous <- c(NA_real_, pct[-length(pct)])
  change <- ifelse(is.na(previous) | previous == 0, NA_real_,
    100 * (pct - previous) / previous)
  change[!stats::complete.cases(summary[by])] <- NA_real_
  change
}

.nis_audit_group_piece <- function(i, summary, code_groups, temp, by) {
  n_cohort <- summary[[temp$cohort]]
  n <- summary[[temp$count[[i]]]]
  weighted <- summary[[temp$weight[[i]]]]
  pct <- ifelse(n_cohort == 0, NA_real_, 100 * n / n_cohort)
  change <- .nis_audit_yoy_change(pct, summary, by)
  dplyr::tibble(
    code_group = code_groups[[i]],
    n_cohort_unweighted = as.integer(n_cohort),
    n_unweighted = as.integer(n),
    n_weighted = as.numeric(weighted),
    pct_within_year = as.numeric(pct),
    yoy_pct_change = as.numeric(change)
  )
}

.nis_audit_bind_periods <- function(pieces, summary, by) {
  periods <- dplyr::as_tibble(summary[by])
  periods <- periods[rep(seq_len(nrow(periods)), times = length(pieces)), , drop = FALSE]
  dplyr::bind_cols(periods, dplyr::bind_rows(pieces))
}

.nis_audit_flag_summary <- function(data, codes, type, system, weight_var, by) {
  temp <- .nis_audit_names(nis_names(data), length(codes)) # nolint: object_usage_linter
  code_groups <- names(codes)
  names(codes) <- temp$flag
  flag_function <- if (type == "pr") nis_flag_pr else nis_flag_dx
  data <- do.call(flag_function, c(list(.data = data), codes, list(system = system)))
  expressions <- .nis_audit_summary_expressions(
    temp$flag, temp$count, temp$weight, weight_var, temp$cohort)
  summary <- .nis_audit_period_summary(data, expressions, by)
  if (nrow(summary) == 0L) return(.nis_audit_empty_output(by, summary, "summary"))
  pieces <- lapply(seq_along(codes), .nis_audit_group_piece,
    summary = summary, code_groups = code_groups, temp = temp, by = by)
  .nis_audit_bind_periods(pieces, summary, by)
}

.nis_audit_slot_names <- function(data_names, slots, system) {
  stem <- paste0(if (system == "icd10") "I10_", slots)
  slot_names <- grep(paste0("^", stem, "[0-9]+$"), data_names, value = TRUE)
  if (length(slot_names) == 0L) {
    cli::cli_abort(paste(
      "No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} {slots} columns",
      "({stem}<n>) were found."
    ))
  }
  slot_names
}

.nis_audit_inventory_temp <- function(input_names) {
  candidates <- c(".nis_audit_code", ".nis_audit_weight", ".nis_audit_cohort",
    ".nis_audit_n", ".nis_audit_w")
  unique_names <- make.unique(c(input_names, candidates), sep = "_")[-seq_along(input_names)]
  stats::setNames(as.list(unique_names), c("code", "weight", "cohort", "count", "total"))
}

.nis_audit_observed_pairs <- function(values, codes) {
  pairs <- lapply(names(codes), function(group) {
    prefixes <- normalize_prefixes(codes[[group]])
    starts <- lapply(prefixes, function(prefix) startsWith(values, prefix))
    matched <- values[Reduce(`|`, starts)]
    dplyr::tibble(
      code_group = rep(group, max(length(matched), 1L)),
      code = if (length(matched) > 0L) matched else NA_character_
    )
  })
  dplyr::bind_rows(pairs)
}

.nis_audit_status <- function(n, sparse_n) {
  dplyr::case_when(n == 0 ~ "absent", n <= sparse_n ~ "sparse", .default = "observed")
}

# Long form: one row per discharge and distinct code, so each discharge counts
# once per code and the width never depends on the number of codes.
.nis_audit_lazy_codes <- function(data, slot_names, temp, weight_var, by) {
  con <- dbplyr::remote_con(data)
  slots <- paste0("CAST(", DBI::dbQuoteIdentifier(con, slot_names), " AS VARCHAR)", collapse = ", ")
  codes <- dbplyr::sql(paste0("UNNEST(list_distinct([", slots, "]))"))
  data |>
    dplyr::mutate(!!temp$weight := !!rlang::sym(weight_var)) |>
    dplyr::mutate(!!temp$code := !!codes) |>
    dplyr::select(dplyr::all_of(c(by, temp$weight, temp$code)))
}

.nis_audit_frame_codes <- function(data, slot_names, temp, weight_var, by) {
  slots <- lapply(slot_names, function(column) as.character(data[[column]]))
  long <- dplyr::tibble(row = rep(seq_len(nrow(data)), times = length(slots)), code = unlist(slots))
  long <- dplyr::distinct(long[!is.na(long$code), ])
  data[[temp$weight]] <- data[[weight_var]]
  rows <- dplyr::select(data, dplyr::all_of(c(by, temp$weight)))
  rows <- dplyr::slice(rows, long$row)
  rows[[temp$code]] <- long$code
  rows
}

.nis_audit_code_counts <- function(data, eligibility, slot_names, prefixes, temp, weight_var, by) {
  if (!is.null(eligibility)) data <- dplyr::filter(data, !!eligibility)
  lazy <- inherits(data, "tbl_sql")
  build <- if (lazy) .nis_audit_lazy_codes else .nis_audit_frame_codes
  matched <- if (lazy) nis_sql_match(prefixes, temp$code) else frame_match(prefixes, temp$code) # nolint: object_usage_linter
  expressions <- list(rlang::expr(dplyr::n()), rlang::expr(sum(!!rlang::sym(temp$weight), na.rm = TRUE)))
  names(expressions) <- c(temp$count, temp$total)
  build(data, slot_names, temp, weight_var, by) |>
    dplyr::filter(!!matched) |>
    dplyr::group_by(!!!rlang::syms(c(by, temp$code))) |>
    dplyr::summarise(!!!expressions, .groups = "drop") |>
    nis_collect() # nolint: object_usage_linter
}

.nis_audit_inventory_grid <- function(periods, pairs, counts, temp, by, sparse_n) {
  n_periods <- nrow(periods)
  grid <- dplyr::bind_cols(
    periods[rep(seq_len(n_periods), times = nrow(pairs)), , drop = FALSE],
    pairs[rep(seq_len(nrow(pairs)), each = n_periods), , drop = FALSE]
  )
  counts <- dplyr::rename(counts, code = !!temp$code)
  grid <- dplyr::left_join(grid, counts, by = c(by, "code"))
  n <- dplyr::coalesce(as.integer(grid[[temp$count]]), 0L)
  grid[["n_cohort_unweighted"]] <- as.integer(grid[[temp$cohort]])
  grid[["n_unweighted"]] <- n
  grid[["n_weighted"]] <- dplyr::coalesce(as.numeric(grid[[temp$total]]), 0)
  grid[["status"]] <- .nis_audit_status(n, sparse_n)
  dplyr::select(grid, dplyr::all_of(c(by, .nis_audit_inventory_names)))
}

.nis_audit_inventory <- function(data, codes, type, system, weight_var, by, sparse_n) {
  data <- dplyr::ungroup(data)
  data_names <- nis_names(data) # nolint: object_usage_linter
  slots <- if (type == "pr") "PR" else "DX"
  slot_names <- .nis_audit_slot_names(data_names, slots, system)
  eligibility <- code_system_filter(data, data_names, slots, system) # nolint: object_usage_linter
  temp <- .nis_audit_inventory_temp(data_names)

  cohort_expression <- stats::setNames(list(rlang::expr(dplyr::n())), temp$cohort)
  periods <- .nis_audit_period_summary(data, cohort_expression, by)
  if (nrow(periods) == 0L) return(.nis_audit_empty_output(by, periods, "inventory"))

  prefixes <- unique(unlist(lapply(codes, normalize_prefixes))) # nolint: object_usage_linter
  counts <- .nis_audit_code_counts(data, eligibility, slot_names, prefixes, temp, weight_var, by)
  pairs <- .nis_audit_observed_pairs(sort(unique(counts[[temp$code]])), codes)
  .nis_audit_inventory_grid(periods, pairs, counts, temp, by, sparse_n)
}

#' Audit code-group frequencies across periods
#'
#' Counts discharges matching each named code-prefix group by period. A
#' discharge is counted once per group, even when multiple slots match.
#' Prefix matching follows [nis_flag_pr()] or [nis_flag_dx()], according to
#' `type`. The complete grid of observed periods and code groups is returned,
#' with zero counts where a group has no matches.
#' Counts apply only to the selected code system; zero does not mean the code
#' is absent under another system. Audits across the 2015 ICD transition need
#' separate calls for each system. The change compares with the previous
#' observed period in sorted order.
#'
#' `by` may name several columns, such as `c("YEAR", "DQTR")`. A period is
#' then one observed combination of their values, sorted by the columns in the
#' order given. A period with a missing value in any component is kept as its
#' own row, sorted after every complete period. Combinations that do not occur
#' in the data are not added. With several columns, no unambiguous year
#' comparison can be inferred, because adjacent combinations may be quarters
#' of one year or the boundary between two other components. `yoy_pct_change`
#' is therefore `NA` in every row; compare `pct_within_year` across the
#' periods you care about instead.
#'
#' With `output = "inventory"`, the function instead lists the full codes
#' observed in the selected slots that start with each group's prefixes, with
#' unweighted and weighted discharge counts for every period. A discharge is
#' counted once per code, even when the code occupies several slots. Each
#' observed code is listed for every period, so a code that is rare in some
#' periods or missing from them is visible. `status` is `"absent"` when the
#' code has no matches in the period, `"sparse"` when its unweighted count is
#' at least one and at most `sparse_n`, and `"observed"` otherwise. A group
#' that matches no observed code is returned with `code` missing and status
#' `"absent"` in every period. Counts are aggregated in the database for lazy
#' inputs, so only period-by-code counts are collected, however many codes a
#' prefix matches. The counts are exact, so apply your disclosure rules (see
#' [nis_suppress()]) before sharing them.
#'
#' @template dot-data
#' @param codes A named character vector or named list of character vectors.
#'   Each name is a `code_group`; each value contains prefixes. Names must be
#'   non-empty and unique.
#' @param cohort Optional tidy-evaluation logical expression defining the
#'   cohort. Rows where it evaluates to `NA` are excluded.
#' @param by Names of one or more existing columns defining periods, with no
#'   duplicates.
#' @param type Whether to match diagnosis (`"dx"`) or procedure (`"pr"`)
#'   slots.
#' @param system Code system of the slots: `"icd10"` (default) or `"icd9"`.
#' @param weight_var Name of the survey weight column, defaulting to
#'   `"DISCWT"`.
#'   Values in the selected cohort must be finite, non-missing numeric values.
#' @param output `"summary"` (default) for code-group frequencies or
#'   `"inventory"` for observed code matches by period.
#' @param sparse_n Largest unweighted count flagged `"sparse"` in the
#'   inventory. Defaults to 10, matching [nis_suppress()]. Used only when
#'   `output = "inventory"`.
#'
#' @return A collected tibble. For `output = "summary"`, the period columns
#'   from `by`, `code_group`, `n_cohort_unweighted`, `n_unweighted`,
#'   `n_weighted`, `pct_within_year`, and `yoy_pct_change`. The change is the
#'   relative percent change in `pct_within_year` versus the previous observed
#'   period in sorted order. It is `NA` for the first period, a period with a
#'   missing value, when the previous period's percentage is zero, and in every
#'   row when `by` names more than one column.
#'   For `output = "inventory"`, the period columns, `code_group`, `code`,
#'   `n_cohort_unweighted`, `n_unweighted`, `n_weighted`, and `status`.
#' @family cohort-definition
#' @seealso [Code transitions and sensitivity](articles/code-transitions.html).
#' @export
#' @examples
#' toy_data <- dplyr::tibble(
#'   YEAR = c(2018L, 2018L, 2019L, 2019L, 2020L, 2020L),
#'   I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02803ZZ", "02803ZZ", "02803ZZ"),
#'   DISCWT = rep(5, 6)
#' )
#' nis_audit_code_transition(toy_data,
#'   codes = c(myectomy = "02UG0JZ", ablation = "02803ZZ"))
#'
#' # Observed full codes by period, with absent and sparse periods flagged
#' nis_audit_code_transition(toy_data,
#'   codes = c(myectomy = "02UG", ablation = "0280"), output = "inventory")
#'
#' # Periods defined by several columns
#' toy_data$DQTR <- c(1L, 2L, 1L, 2L, 1L, 2L)
#' nis_audit_code_transition(toy_data, c(myectomy = "02UG0JZ"),
#'   by = c("YEAR", "DQTR"))
nis_audit_code_transition <- function(.data, codes, cohort = NULL, by = "YEAR",
                                      type = c("pr", "dx"),
                                      system = c("icd10", "icd9"),
                                      weight_var = "DISCWT",
                                      output = c("summary", "inventory"),
                                      sparse_n = 10L) {
  type <- match.arg(type)
  system <- match.arg(system)
  output <- match.arg(output)

  by <- unname(by)
  .nis_audit_validate_by(.data, by, output)
  .nis_audit_validate_weight(.data, weight_var)
  .nis_audit_validate_sparse_n(sparse_n)
  codes <- .nis_audit_validate_codes(codes)

  cohort_quo <- rlang::enquo(cohort)
  data <- .nis_audit_filter_cohort(.data, cohort_quo, by)
  .nis_audit_check_weight_values(data, weight_var)

  if (output == "inventory") {
    return(.nis_audit_inventory(data, codes, type, system, weight_var, by, sparse_n))
  }
  .nis_audit_flag_summary(data, codes, type, system, weight_var, by)
}
