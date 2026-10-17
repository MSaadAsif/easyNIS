#' Prepare a cohort survey design
#'
#' Collects cohort rows and one zero-domain placeholder per hospital-year with
#' no cohort discharges, then builds a nested NIS survey design. The
#' placeholder-row method is experimental and is gated against a full-data
#' design. After this function returns, `filter()` may only narrow the declared
#' cohort; it cannot define a new cohort.
#' Hospital geography columns are optional. Hospital and stratum identifiers
#' are scoped by year (`YEAR` + `HOSP_NIS` and `YEAR` + `NIS_STRATUM`), because
#' HCUP reassigns hospital numbers annually and 2023 stratum codes are
#' sequential. Costs and charges use `TOTCHG` only, unless `charges` names
#' another column such as `TOTCHG_2023`; nothing is coalesced silently, because
#' the 2023 field is not comparable to earlier-year `TOTCHG`. The 2023 layout
#' facts (`TOTCHG_2023`, removed `HOSP_REGION` and `HOSP_DIVISION`, sequential
#' strata) are UNVERIFIED against official HCUP 2023 documentation and real 2023
#' data.
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
#' @param annualize Divide discharge weights by the number of distinct `YEAR`
#'   values among valid-design discharges. A year counts as one whole year
#'   however much of it is present, so a partial-year era such as the ICD-10
#'   fourth quarter of 2015 counts the same as a full year, and a year with no
#'   cohort discharges still counts. Divide by your own factor with
#'   [nis_reweight()] if you need a different convention.
#' @param dollars Optional reference dollar year for adjusted costs and charges.
#'   When supplied, keep `CCR_NIS` and the `charges` column.
#' @param charges Name of the total-charge column used for adjusted costs and
#'   charges. Defaults to `"TOTCHG"`. Use `"TOTCHG_2023"` for 2023-only
#'   analyses, or build a pooled column explicitly with
#'   `dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG))` before
#'   calling; either choice mixes charge definitions across years.
#'
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' design <- nis_design(
#'   nis,
#'   cohort = heart_failure & AGE >= 50,
#'   keep = c(AGE, FEMALE, TOTCHG, CCR_NIS),
#'   dollars = 2024
#' )
#' srvyr::summarise(
#'   design,
#'   discharges = srvyr::survey_total(),
#'   mean_age = srvyr::survey_mean(AGE)
#' )
nis_design <- function(.data, cohort, keep, annualize = FALSE, dollars = NULL,
                       charges = "TOTCHG") {
  if (!is.character(charges) || length(charges) != 1L || is.na(charges)) {
    cli::cli_abort("`charges` must be a single column name.")
  }
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
  # nolint start: object_usage_linter. Data-masked dplyr expressions.
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
  # nolint end
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
  stratum_counts <- dplyr::count(hospital_rows, YEAR, HOSP_NIS) # nolint: object_usage_linter. dplyr data mask.
  if (any(stratum_counts$n != 1L)) {
    cli::cli_abort("Each hospital must map to one stratum within a year.")
  }

  # Scan 2 keeps valid discharges whose cohort value is TRUE or missing, so
  # the cohort expression runs once per discharge. Missing values are counted
  # here and dropped.
  # nolint start: object_usage_linter. Data-masked dplyr expressions.
  collected <- prepared |>
    dplyr::filter(.nis_valid, dplyr::coalesce(.nis_cohort, TRUE)) |>
    dplyr::select(dplyr::all_of(selected), .nis_cohort) |>
    nis_collect()
  # nolint end
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

  hospital_years <- sort(unique(hospital_rows$YEAR))
  no_cohort_years <- setdiff(hospital_years, cohort_rows$YEAR)
  if (length(no_cohort_years) > 0L) {
    cli::cli_warn(c(
      "No cohort discharges in {cli::qty(length(no_cohort_years))}year{?s} {.val {no_cohort_years}}.",
      i = "Those years contribute only placeholder rows, but still count as a year for `annualize`."
    ))
  }

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

  has_cost_inputs <- all(c(charges, "CCR_NIS") %in% keep_names)
  if (!is.null(dollars) && !has_cost_inputs) {
    cli::cli_abort("Keep both {.field {charges}} and `CCR_NIS` when requesting `dollars`.")
  }
  # nolint next: object_usage_linter. Function is defined in this package.
  combined <- nis_label(combined)
  if (has_cost_inputs) {
    charge_years <- unique(cohort_rows$YEAR)
    missing_charge_years <- charge_years[vapply(charge_years, function(year) {
      all(is.na(cohort_rows[[charges]][cohort_rows$YEAR == year]))
    }, logical(1))]
    if (length(missing_charge_years) > 0L) {
      cli::cli_warn(c(
        paste0(
          "`{charges}` is entirely missing in ",
          "{cli::qty(length(missing_charge_years))}year{?s} {.val {sort(missing_charge_years)}}; ",
          "adjusted costs and charges are `NA` there."
        ),
        i = "Name the right column with `charges`, or build one pooled column with `dplyr::mutate()` first."
      ))
    }
    if (is.null(dollars)) dollars <- max(hospital_rows$YEAR)
    # nolint next: object_usage_linter. Function is defined in this package.
    combined <- nis_cost(combined, dollars = dollars, charges = charges)
  }

  # nolint next: object_usage_linter. Used by cli interpolation below.
  hospitals <- length(unique(paste(cohort_rows$YEAR, cohort_rows$HOSP_NIS)))
  # nolint next: object_usage_linter. Used by cli interpolation below.
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
#'   an unquoted numeric column name in the design data. They are matched to
#'   rows by position, so take them from `design$variables` in that order (for
#'   example, fit the propensity model on `design$variables`) and do not
#'   reorder or subset the rows first.
#'
#' @section Weighted totals:
#' The result multiplies the discharge weights by `weights`, so
#' `survey_total()` and similar totals no longer estimate national discharge
#' counts. Use the result for ratios, means and model estimates, and report
#' national counts from the design before reweighting. Each call multiplies the
#' weights again, so call `nis_reweight()` once on the result of
#' [nis_design()]; calling it on an already reweighted design compounds the
#' weights.
#'
#' @return A filtered `srvyr::tbl_svy` survey design.
#' @export
#' @examples
#' nis <- nis_open(nis_example(years = 2019:2020)) |>
#'   nis_flag_dx(heart_failure = "I50")
#' design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE))
#'
#' # Illustrative weights only; use weights from your own validated model
#' reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
#' srvyr::summarise(reweighted, weighted_total = srvyr::survey_total())
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
  # nolint start: object_usage_linter. srvyr/dplyr data-masked fields.
  design <- srvyr::as_survey_design(
    combined,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)
  # nolint end
  attr(design, "nis_placeholder_rows") <- combined[!combined$.in_cohort, , drop = FALSE]
  attr(design, "nis_cohort_rows") <- sum(combined$.in_cohort)
  design
}

nis_collect <- function(x) {
  if (is.data.frame(x)) x else dplyr::collect(x)
}
