#' Prepare a cohort survey design
#'
#' Collects cohort rows and one zero-domain placeholder per hospital-year with
#' no cohort discharges, then builds a nested NIS survey design. The
#' placeholder-row method is experimental and is gated against a full-data
#' design. After this function returns, `filter()` may only narrow the declared
#' cohort; it cannot define a new cohort.
#'
#' @param .data Lazy Arrow query or data frame.
#' @param cohort Logical data-masked cohort expression. Missing values are
#'   counted and treated as outside the cohort.
#' @param keep Tidyselect expression naming analysis columns to collect.
#' @param annualize Divide discharge weights by the number of included years.
#' @param dollars Optional reference dollar year for adjusted costs and charges.
#'
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @export
nis_design <- function(.data, cohort, keep, annualize = FALSE, dollars = NULL) {
  if (length(annualize) != 1L || !is.logical(annualize) || is.na(annualize)) {
    cli::cli_abort("`annualize` must be `TRUE` or `FALSE`.")
  }
  reserved <- c(".in_cohort", ".nis_cohort", ".cohort_missing",
    ".nis_psu", ".nis_stratum", ".nis_weight")
  if (any(reserved %in% names(.data))) {
    cli::cli_abort("Input column names beginning with the internal design names are reserved.")
  }

  design_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
  absent <- setdiff(design_fields, names(.data))
  if (length(absent) > 0L) {
    cli::cli_abort("`.data` is missing design column{?s} {.val {absent}}.")
  }
  data_names <- names(.data)
  select_data <- stats::setNames(as.list(seq_along(data_names)), data_names)
  keep_names <- names(tidyselect::eval_select(rlang::enquo(keep),
    data = select_data))
  if (any(startsWith(keep_names, "."))) {
    cli::cli_abort("`keep` cannot select internal or dot-prefixed columns.")
  }
  selected <- unique(c(design_fields, keep_names))

  cohort_quo <- rlang::enquo(cohort)
  prepared <- dplyr::mutate(.data, .nis_cohort = !!cohort_quo)
  prepared <- dplyr::mutate(
    prepared,
    .in_cohort = dplyr::coalesce(.nis_cohort, FALSE),
    .cohort_missing = is.na(.nis_cohort)
  )

  missing_cohort <- prepared |>
    dplyr::filter(.cohort_missing) |>
    dplyr::summarise(n = dplyr::n()) |>
    nis_collect()
  missing_count <- if (nrow(missing_cohort) == 0L) 0L else missing_cohort$n[[1L]]
  if (missing_count > 0L) {
    cli::cli_inform("Treated {missing_count} missing cohort value{?s} as outside the cohort.")
  }

  hospital_rows <- prepared |>
    dplyr::select(dplyr::all_of(design_fields)) |>
    dplyr::group_by(YEAR, HOSP_NIS, NIS_STRATUM) |>
    dplyr::summarise(DISCWT = min(DISCWT, na.rm = TRUE), .groups = "drop") |>
    nis_collect()
  if (nrow(hospital_rows) == 0L || anyNA(hospital_rows[design_fields])) {
    cli::cli_abort("NIS design fields must be present for every hospital-year.")
  }
  if (any(!is.finite(hospital_rows$DISCWT)) || any(hospital_rows$DISCWT <= 0)) {
    cli::cli_abort("`DISCWT` must contain a positive finite weight for every hospital-year.")
  }
  stratum_counts <- dplyr::count(hospital_rows, YEAR, HOSP_NIS)
  if (any(stratum_counts$n != 1L)) {
    cli::cli_abort("Each hospital must map to one stratum within a year.")
  }

  cohort_rows <- prepared |>
    dplyr::filter(.in_cohort) |>
    dplyr::select(dplyr::all_of(selected), .in_cohort) |>
    nis_collect()
  if (anyNA(cohort_rows$DISCWT) || any(!is.finite(cohort_rows$DISCWT)) ||
      any(cohort_rows$DISCWT <= 0)) {
    cli::cli_abort("`DISCWT` must be positive and finite for every cohort discharge.")
  }
  cohort_hospitals <- unique(cohort_rows[c("YEAR", "HOSP_NIS")])
  empty_hospitals <- dplyr::anti_join(hospital_rows, cohort_hospitals,
    by = c("YEAR", "HOSP_NIS"))

  placeholders <- cohort_rows[rep(NA_integer_, nrow(empty_hospitals)), , drop = FALSE]
  if (nrow(empty_hospitals) > 0L) {
    for (field in design_fields) placeholders[[field]] <- empty_hospitals[[field]]
    placeholders$.in_cohort <- FALSE
  }
  combined <- dplyr::bind_rows(cohort_rows, placeholders)
  combined$.nis_psu <- paste(combined$YEAR, combined$HOSP_NIS, sep = "::")
  combined$.nis_stratum <- paste(combined$YEAR, combined$NIS_STRATUM, sep = "::")
  year_count <- length(unique(hospital_rows$YEAR))
  combined$.nis_weight <- combined$DISCWT / if (annualize) year_count else 1

  combined <- nis_label(combined)
  has_cost_inputs <- all(c("TOTCHG", "CCR_NIS") %in% keep_names)
  if (!is.null(dollars) && !has_cost_inputs) {
    cli::cli_abort("Keep both `TOTCHG` and `CCR_NIS` when requesting `dollars`.")
  }
  if (has_cost_inputs) {
    if (is.null(dollars)) dollars <- max(hospital_rows$YEAR)
    combined <- nis_cost(combined, dollars = dollars)
  }

  hospitals <- length(unique(paste(cohort_rows$YEAR, cohort_rows$HOSP_NIS)))
  weighted_n <- sum(cohort_rows$DISCWT) / if (annualize) year_count else 1
  cli::cli_inform(paste0(
    "Cohort: {nrow(cohort_rows)} discharges; weighted N {format(weighted_n, big.mark = ',')}; ",
    "{hospitals} hospitals across {year_count} years."
  ))
  nis_cohort_design(combined)
}

#' Reweight a cohort survey design
#'
#' Multiplies cohort discharge survey weights by supplied propensity weights,
#' retains the placeholder rows for hospital-years without cohort discharges,
#' and rebuilds the nested survey design. This experimental method is intended
#' for analysts who have validated their weighting specification against a
#' full-data reference design.
#'
#' @param design A result of [nis_design()].
#' @param weights Numeric weights aligned with the cohort rows of `design`, or
#'   an unquoted numeric column name in the design data.
#'
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @export
nis_reweight <- function(design, weights) {
  placeholders <- attr(design, "nis_placeholder_rows", exact = TRUE)
  cohort_rows <- attr(design, "nis_cohort_rows", exact = TRUE)
  if (!inherits(design, "tbl_svy") || !is.data.frame(placeholders) ||
      is.null(cohort_rows)) {
    cli::cli_abort("`design` must be a result of `nis_design()`.")
  }
  variables <- design$variables
  if (nrow(variables) != cohort_rows) {
    cli::cli_abort(c(
      "`design` has been narrowed with `filter()`.",
      i = "Call `nis_reweight()` before narrowing the cohort."
    ))
  }

  weight_values <- rlang::eval_tidy(rlang::enquo(weights), data = variables)
  if (!is.numeric(weight_values) || !is.null(dim(weight_values))) {
    cli::cli_abort("`weights` must be a numeric vector or numeric column.")
  }
  if (length(weight_values) != nrow(variables)) {
    cli::cli_abort("`weights` must have one value per cohort row in `design`.")
  }
  if (any(!is.finite(weight_values))) {
    cli::cli_abort("`weights` must contain only finite values.")
  }
  if (any(weight_values <= 0)) {
    cli::cli_abort("`weights` must be positive.")
  }

  variables$.nis_weight <- variables$.nis_weight * weight_values
  nis_cohort_design(dplyr::bind_rows(variables, placeholders))
}

# Cohort rows plus placeholder rows (`.in_cohort == FALSE`) in one nested
# design, filtered to the cohort. The placeholders and the cohort row count
# stay on the result so `nis_reweight()` can rebuild the design.
nis_cohort_design <- function(combined) {
  design <- srvyr::as_survey_design(
    combined,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)
  attr(design, "nis_placeholder_rows") <- combined[!combined$.in_cohort, , drop = FALSE]
  attr(design, "nis_cohort_rows") <- sum(combined$.in_cohort)
  design
}

nis_collect <- function(x) {
  if (is.data.frame(x)) x else dplyr::collect(x)
}
