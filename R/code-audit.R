#' Audit code-group frequencies across periods
#'
#' Counts discharges matching each named code-prefix group by period. A
#' discharge is counted once per group, even when multiple slots match.
#' Prefix matching follows [nis_flag_pr()] or [nis_flag_dx()], according to
#' `type`. The complete grid of observed periods and code groups is returned,
#' with zero counts where a group has no matches.
#'
#' @param .data A data frame or lazy Arrow query.
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
#'   and `yoy_pct_change`. Year-over-year change is the relative percent change
#'   in `pct_within_year`; it is `NA` for the first period and when the previous
#'   period's percentage is zero.
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

  if (!is.character(by) || length(by) != 1L || is.na(by) || !nzchar(by) ||
      !by %in% names(.data)) {
    cli::cli_abort("`by` must be the name of one existing column.")
  }
  if (!is.character(weight_var) || length(weight_var) != 1L ||
      is.na(weight_var) || !nzchar(weight_var) ||
      !weight_var %in% names(.data)) {
    cli::cli_abort("`weight_var` must be the name of one existing column.")
  }
  if (!(is.character(codes) || is.list(codes)) || length(codes) == 0L ||
      is.null(names(codes)) || anyNA(names(codes)) ||
      any(!nzchar(names(codes))) || anyDuplicated(names(codes))) {
    cli::cli_abort("`codes` must be a non-empty named vector or list with unique, non-empty names.")
  }
  codes <- lapply(as.list(codes), function(prefixes) {
    if (!is.character(prefixes) || length(prefixes) == 0L || anyNA(prefixes)) {
      cli::cli_abort("Each code group must contain non-missing character prefixes.")
    }
    prefixes
  })
  code_groups <- names(codes)

  cohort_quo <- rlang::enquo(cohort)
  data <- .data
  if (!rlang::quo_is_null(cohort_quo)) {
    data <- dplyr::filter(data, !!cohort_quo)
  }

  flag_names <- paste0(".nis_audit_flag_", seq_along(codes))
  while (any(flag_names %in% names(data))) {
    flag_names <- paste0(flag_names, "_")
  }
  names(codes) <- flag_names
  flag_function <- if (type == "pr") nis_flag_pr else nis_flag_dx
  data <- do.call(flag_function, c(list(.data = data), codes,
    list(system = system)))

  used_names <- c(names(.data), by)
  unique_temp_name <- function(name) {
    while (name %in% used_names) name <- paste0(name, "_")
    used_names <<- c(used_names, name)
    name
  }
  cohort_count_name <- unique_temp_name(".nis_audit_cohort")
  count_names <- vapply(seq_along(codes), function(i) {
    unique_temp_name(paste0(".nis_audit_n_", i))
  }, character(1))
  weight_names <- vapply(seq_along(codes), function(i) {
    unique_temp_name(paste0(".nis_audit_w_", i))
  }, character(1))

  expressions <- list()
  expressions[[cohort_count_name]] <- rlang::expr(dplyr::n())
  for (i in seq_along(flag_names)) {
    flag <- rlang::sym(flag_names[[i]])
    expressions[[count_names[[i]]]] <- rlang::expr(sum(as.integer(!!flag), na.rm = TRUE))
    expressions[[weight_names[[i]]]] <- rlang::expr(sum(
      dplyr::if_else(!!flag, !!rlang::sym(weight_var), 0), na.rm = TRUE
    ))
  }
  summary <- data |>
    dplyr::group_by(!!rlang::sym(by)) |>
    dplyr::summarise(!!!expressions, .groups = "drop") |>
    dplyr::collect()

  if (nrow(summary) == 0L) {
    output <- dplyr::tibble(
      code_group = character(), n_cohort_unweighted = integer(),
      n_unweighted = integer(), n_weighted = double(),
      pct_within_year = double(), yoy_pct_change = double()
    )
    output[[by]] <- summary[[by]]
    return(dplyr::select(output, !!rlang::sym(by), dplyr::everything()))
  }

  summary <- summary[order(summary[[by]]), , drop = FALSE]
  pieces <- lapply(seq_along(codes), function(i) {
    n_cohort <- summary[[cohort_count_name]]
    n <- summary[[count_names[[i]]]]
    weighted <- summary[[weight_names[[i]]]]
    pct <- ifelse(n_cohort == 0, NA_real_, 100 * n / n_cohort)
    previous <- c(NA_real_, pct[-length(pct)])
    change <- ifelse(is.na(previous) | previous == 0, NA_real_,
      100 * (pct - previous) / previous)
    dplyr::tibble(
      code_group = code_groups[[i]],
      n_cohort_unweighted = n_cohort,
      n_unweighted = n,
      n_weighted = as.numeric(weighted),
      pct_within_year = as.numeric(pct),
      yoy_pct_change = as.numeric(change)
    )
  })
  output <- dplyr::bind_rows(pieces)
  output[[by]] <- rep(summary[[by]], times = length(codes))
  output <- dplyr::select(output, !!rlang::sym(by), dplyr::everything())
  output[order(match(output$code_group, code_groups), output[[by]]), , drop = FALSE]
}
