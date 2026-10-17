#' Prepare a cohort survey design
#'
#' Collects cohort rows and one zero-domain placeholder per hospital-year with
#' no cohort discharges, then builds a nested NIS survey design. The
#' placeholder-row method is experimental and is gated against a full-data
#' design. After this function returns, `filter()` may only narrow the declared
#' cohort; it cannot define a new cohort.
#'
#' Discharges whose `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT` is missing,
#' non-finite, or not positive cannot be placed in a survey design. They are
#' excluded before the cohort is applied, with a warning that gives their
#' number. The query is scanned twice: once over the four design columns, and
#' once to collect the cohort rows, so the cohort expression is evaluated one
#' time over the full data.
#'
#' @param .data Lazy Arrow query or data frame.
#' @param cohort Logical data-masked cohort expression. Missing values are
#'   counted and treated as outside the cohort. Only valid-design discharges
#'   are counted.
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
  reserved <- c(".in_cohort", ".nis_cohort", ".nis_valid",
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
  prepared <- dplyr::mutate(
    .data,
    .nis_cohort = !!cohort_quo,
    .nis_valid = dplyr::coalesce(
      YEAR > 0 & HOSP_NIS > 0 & NIS_STRATUM > 0 & is.finite(DISCWT) & DISCWT > 0,
      FALSE
    )
  )

  # Scan 1 reads only the design columns, because Arrow drops the cohort
  # expression from the projection when it is not selected.
  design_groups <- prepared |>
    dplyr::group_by(.nis_valid, YEAR, HOSP_NIS, NIS_STRATUM) |>
    dplyr::summarise(
      DISCWT = min(dplyr::if_else(.nis_valid, DISCWT, Inf)),
      n = dplyr::n(),
      .groups = "drop"
    ) |>
    nis_collect()
  excluded_count <- sum(design_groups$n[!design_groups$.nis_valid])
  if (excluded_count > 0L) {
    cli::cli_warn(paste0(
      "Excluded {excluded_count} discharge{?s} with a missing or invalid ",
      "`YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT` before applying the cohort."
    ))
  }
  hospital_rows <- design_groups[design_groups$.nis_valid, design_fields]
  if (nrow(hospital_rows) == 0L) {
    cli::cli_abort("No discharges have valid design fields.")
  }
  stratum_counts <- dplyr::count(hospital_rows, YEAR, HOSP_NIS)
  if (any(stratum_counts$n != 1L)) {
    cli::cli_abort("Each hospital must map to one stratum within a year.")
  }

  # Scan 2 keeps valid discharges whose cohort value is TRUE or missing, so
  # the cohort expression runs once per discharge. Missing values are counted
  # here and dropped.
  collected <- prepared |>
    dplyr::filter(.nis_valid, dplyr::coalesce(.nis_cohort, TRUE)) |>
    dplyr::select(dplyr::all_of(selected), .nis_cohort) |>
    nis_collect()
  if (!is.logical(collected$.nis_cohort)) {
    cli::cli_abort("`cohort` must evaluate to a logical vector.")
  }
  missing_count <- sum(is.na(collected$.nis_cohort))
  if (missing_count > 0L) {
    cli::cli_inform("Treated {missing_count} missing cohort value{?s} as outside the cohort.")
  }
  cohort_rows <- collected[which(collected$.nis_cohort), selected, drop = FALSE]
  cohort_rows$.in_cohort <- rep(TRUE, nrow(cohort_rows))
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

  design <- srvyr::as_survey_design(
    combined,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  )
  hospitals <- length(unique(paste(cohort_rows$YEAR, cohort_rows$HOSP_NIS)))
  weighted_n <- sum(cohort_rows$DISCWT) / if (annualize) year_count else 1
  cli::cli_inform(paste0(
    "Cohort: {nrow(cohort_rows)} discharges; weighted N {format(weighted_n, big.mark = ',')}; ",
    "{hospitals} hospitals across {year_count} years."
  ))
  dplyr::filter(design, .in_cohort)
}

nis_collect <- function(x) {
  if (is.data.frame(x)) x else dplyr::collect(x)
}
