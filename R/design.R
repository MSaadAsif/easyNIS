nis_design_validate <- function(.data, charges, annualize, call) {
  if (!is.character(charges) || length(charges) != 1L || is.na(charges)) {
    cli::cli_abort("`charges` must be a single column name.", call = call)
  }
  if (length(annualize) != 1L || !is.logical(annualize) || is.na(annualize)) {
    cli::cli_abort("`annualize` must be `TRUE` or `FALSE`.", call = call)
  }
  reserved <- c(.nis_cohort_structure_fields, ".in_cohort", ".nis_cohort",
    ".nis_valid", unname(.nis_design_invalid_fields))
  if (!identical(reserved, nis_internal_names(.data, nis_names(.data), reserved))) {
    cli::cli_abort("Input column names beginning with the internal design names are reserved.", call = call)
  }
}

nis_design_fields <- function(.data, keep_quo, call) {
  design_fields <- .nis_design_fields
  data_names <- nis_names(.data)
  absent <- setdiff(design_fields, data_names)
  if (length(absent) > 0L) {
    cli::cli_abort("`.data` is missing design column{?s} {.val {absent}}.", call = call)
  }
  # A zero-row lazy query obtains R column types without collecting discharges.
  select_data <- if (inherits(.data, "tbl_lazy")) {
    nis_collect(utils::head(.data, 0L))
  } else {
    .data
  }
  keep_expr <- rlang::get_expr(keep_quo)
  keep_symbol <- rlang::is_symbol(keep_expr)
  keep_symbol_name <- if (keep_symbol) rlang::as_string(keep_expr) else NULL
  keep_value <- if (keep_symbol && !(keep_symbol_name %in% data_names) &&
    rlang::env_has(rlang::get_env(keep_quo), rlang::as_string(keep_expr), inherit = TRUE)) {
    rlang::env_get(rlang::get_env(keep_quo), rlang::as_string(keep_expr), inherit = TRUE)
  } else {
    keep_expr
  }
  selection <- if (is.character(keep_value)) {
    absent_keep <- setdiff(keep_value, data_names)
    if (length(absent_keep)) {
      cli::cli_abort("`keep` references missing column{?s} {.val {absent_keep}}.", call = call)
    }
    tidyselect::eval_select(rlang::expr(tidyselect::all_of(!!keep_value)),
      data = select_data)
  } else {
    tidyselect::eval_select(keep_quo, data = select_data)
  }
  keep_names <- data_names[unname(selection)]
  keep_map <- stats::setNames(keep_names, names(selection))
  if (any(startsWith(c(keep_names, names(keep_map)), "."))) {
    cli::cli_abort("`keep` cannot select internal or dot-prefixed columns.", call = call)
  }
  selected <- unique(c(design_fields, keep_names))
  list(
    keep_names = keep_names,
    keep_map = keep_map,
    selected = selected,
    quarter_prototype = select_data[["DQTR"]][integer()]
  )
}

nis_design_aliases <- function(combined, fields, cost_fields, alias_sources, call) {
  keep_map <- fields$keep_map
  retained <- unique(c(.nis_design_fields, cost_fields))
  renamed <- names(keep_map) != unname(keep_map)
  conflicts <- intersect(names(keep_map)[renamed], retained)
  if (length(conflicts)) {
    cli::cli_abort("`keep` cannot rename another column to retained field{?s} {.val {conflicts}}.", call = call)
  }
  # Copy simultaneously so swaps and multiple aliases use the original values
  # and labels, including aliases whose names are other HCUP field names.
  aliases <- combined[unname(keep_map)]
  aliases[renamed] <- alias_sources[unname(keep_map[renamed])]
  names(aliases) <- names(keep_map)
  combined <- combined[setdiff(names(combined), setdiff(fields$keep_names, retained))]
  combined[names(aliases)] <- aliases
  combined
}

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
#' @section Invalid design fields:
#' Discharges whose `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT` is missing,
#' non-finite, or not positive are excluded before the cohort is applied.
#' HCUP specifies `DISCWT` as the discharge weight, `NIS_STRATUM` as the
#' stratum, and `HOSP_NIS` as the hospital cluster
#' ([variance guidance](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp);
#' [2017 NIS introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2017.jsp));
#' HCUP also documents missing and invalid coding conventions
#' ([coding conventions](https://hcup-us.ahrq.gov/db/coding.jsp)). Records
#' with invalid values cannot be placed in the documented design as supplied.
#' Exclusion is not a claim that these records have zero population weight or
#' that estimates are unbiased. Report the excluded count and affected fields,
#' and consider whether conclusions could depend on them. The returned design
#' has a `nis_excluded` attribute containing aggregate `total`, `by_field`,
#' and `by_year` counts; `by_year` includes years with exclusions when the
#' year is itself valid. A discharge can fail more than one field.
#'
#' A lazy query is scanned twice. The sample scan summarises design fields,
#' exclusion counts, and quarter coverage when annualizing. The cohort scan
#' evaluates the cohort expression once over the full data and collects the
#' retained analysis columns.
#'
#' @param .data Lazy DuckDB query or data frame. Existing dplyr groups and
#'   rowwise grouping are removed before evaluating `cohort`; aggregate cohort
#'   expressions therefore use the full input, not individual input groups.
#' @param cohort Logical data-masked cohort expression. Missing values are
#'   counted and treated as outside the cohort. Only valid-design discharges
#'   are counted. Untyped SQL `NULL` values are accepted as missing logical
#'   values. Lazy columns are validated using their SQL type; numeric and
#'   character columns are rejected even when all missing.
#' @param keep Tidyselect expression naming analysis columns to collect.
#'   Renaming uses the selected source values and labels. Required design
#'   fields remain under their original names, as do selected cost inputs when
#'   costs are computed. Aliases cannot overwrite these retained fields or
#'   computed cost columns. Type predicates inspect actual columns locally and
#'   a zero-row schema for lazy queries; predicates depending on row values
#'   are therefore not portable across backends.
#' @param annualize Divide discharge weights by the number of distinct `YEAR`
#'   values among valid-design discharges. A year counts as one whole year
#'   however much of it is present, so a partial-year era such as the ICD-10
#'   fourth quarter of 2015 counts the same as a full year, and a year with no
#'   cohort discharges still counts. When `DQTR` is present, a warning identifies
#'   years where the valid-design data has fewer than four quarters. A separate
#'   warning identifies a cohort limited to the ICD-9 (Q1-Q3) or ICD-10 (Q4) part
#'   of 2015. Exclude partial years or use `annualize = FALSE` and apply a
#'   suitable fractional-year factor with [nis_reweight()] if you need a
#'   different convention.
#' @param dollars Optional reference dollar year for adjusted costs and charges.
#'   When supplied, keep `CCR_NIS` and the `charges` column.
#' @param charges Name of the total-charge column used for adjusted costs and
#'   charges. Defaults to `"TOTCHG"`. Use `"TOTCHG_2023"` for 2023-only
#'   analyses, or build a pooled column explicitly with
#'   `dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG))` before
#'   calling; either choice mixes charge definitions across years.
#'
#' @return A filtered `srvyr::tbl_svy` survey design. The analysis data contains
#'   the required design fields, the columns selected by `keep`, and any
#'   computed cost columns. Use [stats::weights()] for the survey weights.
#' @family survey-design
#' @seealso [Survey design and weighting](articles/survey-design.html).
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
  call <- rlang::current_call()
  .data <- dplyr::ungroup(.data)
  nis_design_validate(.data, charges, annualize, call)
  fields <- nis_design_fields(.data, rlang::enquo(keep), call)
  sample <- nis_design_sample(.data, rlang::enquo(cohort), fields$selected,
    fields$quarter_prototype, annualize, call)
  hospital_rows <- sample$hospital_rows
  cohort_rows <- sample$cohort_rows
  no_cohort_years <- setdiff(sample$years, cohort_rows$YEAR)
  if (length(no_cohort_years) > 0L) {
    cli::cli_warn(c(
      "No cohort discharges in {cli::qty(length(no_cohort_years))}year{?s} {.val {no_cohort_years}}.",
      i = "Those years contribute only placeholder rows, but still count as a year for `annualize`."
    ))
  }

  year_count <- length(sample$years)
  divisor <- if (annualize) year_count else 1
  keys <- c("YEAR", "HOSP_NIS")
  hospital_index <- vctrs::vec_match(cohort_rows[keys], hospital_rows[keys])
  has_cohort <- tabulate(hospital_index, nrow(hospital_rows)) > 0L
  empty <- which(!has_cohort)
  if (!is.double(cohort_rows$DISCWT)) cohort_rows$DISCWT <- as.double(cohort_rows$DISCWT)
  discharge_weights <- cohort_rows$DISCWT

  has_cost_inputs <- all(c(charges, "CCR_NIS") %in% fields$keep_names)
  if (!is.null(dollars) && !has_cost_inputs) {
    cli::cli_abort("Keep both {.field {charges}} and `CCR_NIS` when requesting `dollars`.")
  }
  cohort_rows <- nis_label(cohort_rows)
  alias_sources <- cohort_rows[unique(fields$keep_names)]
  if (has_cost_inputs) {
    cost_fields <- c(charges, "CCR_NIS", "charges_adj", "cost_adj")
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
    if (is.null(dollars)) dollars <- max(sample$years)
    cohort_rows <- nis_adjust_costs(cohort_rows, dollars, charges, call,
      cohort_years = sample$years)
    cost_provenance <- nis_cost_provenance(cohort_rows)
  } else {
    cost_fields <- NULL
    cost_provenance <- NULL
  }

  hospitals <- sum(has_cohort)
  weighted_n <- sum(discharge_weights) / divisor
  cli::cli_inform(paste0(
    "Cohort: {nrow(cohort_rows)} discharges; weighted N {format(weighted_n, big.mark = ',')}; ",
    "{hospitals} hospitals across {year_count} years."
  ))
  cohort_rows <- nis_design_aliases(cohort_rows, fields, cost_fields, alias_sources, call)

  # Form the nested labels once per hospital-year. Factor codes retain the
  # original stratum and PSU ordering used by survey's variance calculation.
  psu <- paste(hospital_rows$YEAR, hospital_rows$HOSP_NIS, sep = "::")
  stratum <- paste(hospital_rows$YEAR, hospital_rows$NIS_STRATUM, sep = "::")
  # survey requires nesting when the sample contains just one PSU.
  nest <- nrow(hospital_rows) == 1L
  cluster <- factor(if (nest) psu else paste(stratum, psu, sep = "."))
  indices <- if (length(empty)) c(hospital_index, empty) else hospital_index
  placeholders <- dplyr::tibble(
    .nis_psu = psu[empty],
    .nis_stratum = stratum[empty],
    .nis_weight = hospital_rows$DISCWT[empty] / divisor
  )
  cohort_weights <- discharge_weights / divisor
  structure <- dplyr::tibble(
    .nis_psu = cluster[indices],
    .nis_stratum = factor(stratum)[indices],
    .nis_weight = if (length(empty)) c(cohort_weights, placeholders$.nis_weight) else cohort_weights
  )
  nis_cohort_design(cohort_rows, structure, placeholders, sample$excluded,
    cost_provenance, nest = nest)
}
