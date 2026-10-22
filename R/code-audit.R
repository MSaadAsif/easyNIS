.nis_audit_is_column_name <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

.nis_audit_validate_by <- function(.data, by) {
  if (!.nis_audit_is_column_name(by) ||
      !by %in% nis_names(.data)) { # nolint: object_usage_linter
    cli::cli_abort("`by` must be the name of one existing column.")
  }
}

.nis_audit_validate_weight <- function(.data, weight_var) {
  if (!.nis_audit_is_column_name(weight_var) ||
      !weight_var %in% nis_names(.data)) { # nolint: object_usage_linter
    cli::cli_abort("`weight_var` must be the name of one existing column.")
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
    period <- rlang::sym(by)
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

.nis_audit_empty_output <- function(by, summary) {
  output <- dplyr::tibble(
    code_group = character(), n_cohort_unweighted = integer(),
    n_unweighted = integer(), n_weighted = double(),
    pct_within_year = double(), yoy_pct_change = double()
  )
  output[[by]] <- summary[[by]]
  dplyr::select(output, !!rlang::sym(by), dplyr::everything())
}

.nis_audit_group_piece <- function(i, summary, code_groups, cohort_count_name,
                                   count_names, weight_names, by) {
  n_cohort <- summary[[cohort_count_name]]
  n <- summary[[count_names[[i]]]]
  weighted <- summary[[weight_names[[i]]]]
  pct <- ifelse(n_cohort == 0, NA_real_, 100 * n / n_cohort)
  previous <- c(NA_real_, pct[-length(pct)])
  change <- ifelse(is.na(previous) | previous == 0, NA_real_,
    100 * (pct - previous) / previous)
  change[is.na(summary[[by]])] <- NA_real_
  dplyr::tibble(
    code_group = code_groups[[i]],
    n_cohort_unweighted = as.integer(n_cohort),
    n_unweighted = as.integer(n),
    n_weighted = as.numeric(weighted),
    pct_within_year = as.numeric(pct),
    yoy_pct_change = as.numeric(change)
  )
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
#' @param .data A data frame or lazy DuckDB query.
#' @param codes A named character vector or named list of character vectors.
#'   Each name is a `code_group`; each value contains prefixes. Names must be
#'   non-empty and unique.
#' @param cohort Optional tidy-evaluation logical expression defining the
#'   cohort. Rows where it evaluates to `NA` are excluded.
#' @param by Name of the column defining periods. Must be one existing column.
#' @param type Whether to match diagnosis (`"dx"`) or procedure (`"pr"`)
#'   slots.
#' @param system Code system of the slots: `"icd10"` (default) or `"icd9"`.
#' @param weight_var Name of the survey weight column, defaulting to
#'   `"DISCWT"`.
#'
#' @return A collected tibble with the period column, `code_group`,
#'   `n_cohort_unweighted`, `n_unweighted`, `n_weighted`, `pct_within_year`,
#'   and `yoy_pct_change`. The change is the relative percent change in
#'   `pct_within_year` versus the previous observed period in sorted order. It
#'   is `NA` for the first period, a missing period, or when the previous
#'   period's percentage is zero.
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
nis_audit_code_transition <- function(.data, codes, cohort = NULL, by = "YEAR",
                                      type = c("pr", "dx"),
                                      system = c("icd10", "icd9"),
                                      weight_var = "DISCWT") {
  type <- match.arg(type)
  system <- match.arg(system)

  .nis_audit_validate_by(.data, by)
  output_names <- c("code_group", "n_cohort_unweighted", "n_unweighted",
    "n_weighted", "pct_within_year", "yoy_pct_change")
  if (by %in% output_names) {
    cli::cli_abort("`by` must not have the same name as a summary column.")
  }
  .nis_audit_validate_weight(.data, weight_var)
  codes <- .nis_audit_validate_codes(codes)
  code_groups <- names(codes)

  cohort_quo <- rlang::enquo(cohort)
  data <- .nis_audit_filter_cohort(.data, cohort_quo, by)

  data_names <- nis_names(.data) # nolint: object_usage_linter
  temp_names <- .nis_audit_temporary_names(data_names, length(codes))
  flag_names <- temp_names[seq_along(codes)]
  names(codes) <- flag_names
  flag_function <- if (type == "pr") nis_flag_pr else nis_flag_dx
  data <- do.call(flag_function, c(list(.data = data), codes,
    list(system = system)))

  cohort_count_name <- temp_names[[length(codes) + 1L]]
  count_start <- length(codes) + 2L
  count_names <- temp_names[count_start:(count_start + length(codes) - 1L)]
  weight_start <- count_start + length(codes)
  weight_names <- temp_names[weight_start:(weight_start + length(codes) - 1L)]

  expressions <- .nis_audit_summary_expressions(
    flag_names, count_names, weight_names, weight_var, cohort_count_name)
  summary <- data |>
    dplyr::group_by(!!rlang::sym(by)) |>
    dplyr::summarise(!!!expressions, .groups = "drop") |>
    dplyr::collect()

  if (nrow(summary) == 0L) {
    return(.nis_audit_empty_output(by, summary))
  }

  summary <- summary[order(summary[[by]]), , drop = FALSE]
  pieces <- lapply(seq_along(codes), .nis_audit_group_piece,
    summary = summary, code_groups = code_groups,
    cohort_count_name = cohort_count_name, count_names = count_names,
    weight_names = weight_names, by = by)
  output <- dplyr::bind_rows(pieces)
  output[[by]] <- rep(summary[[by]], times = length(codes))
  output <- dplyr::select(output, !!rlang::sym(by), dplyr::everything())
  output[order(match(output$code_group, code_groups), output[[by]]), , drop = FALSE]
}
