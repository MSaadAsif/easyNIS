nis_design_input <- function(data) {
  if (!inherits(data, "tbl_sql")) {
    return(data)
  }
  query <- data$lazy_query
  # Reuse the rendered projection across the design queries. Preserve
  # dbplyr's original query when row selection or window context is pending.
  keep_query <- c(
    !inherits(query, "lazy_select_query"),
    isTRUE(query$distinct),
    !is.null(query$limit),
    length(dbplyr::op_sort(data)) > 0L,
    !is.null(dbplyr::op_frame(data))
  )
  if (any(keep_query)) {
    return(data)
  }
  nis_duckdb_translate_errors(dplyr::collapse(data))
}

nis_design_validate <- function(.data, charges, annualize, call, saved = FALSE) {
  if (!is.character(charges) || length(charges) != 1L || is.na(charges)) {
    cli::cli_abort("`charges` must be a single column name.", call = call)
  }
  if (length(annualize) != 1L || !is.logical(annualize) || is.na(annualize)) {
    cli::cli_abort("`annualize` must be `TRUE` or `FALSE`.", call = call)
  }
  reserved <- c(
    .nis_cohort_structure_fields,
    if (!saved) ".in_cohort",
    ".nis_cohort",
    ".nis_valid",
    unname(.nis_design_invalid_fields)
  )
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
  keep_value <- if (
    keep_symbol &&
      !(keep_symbol_name %in% data_names) &&
      rlang::env_has(rlang::get_env(keep_quo), rlang::as_string(keep_expr), inherit = TRUE)
  ) {
    rlang::env_get(rlang::get_env(keep_quo), rlang::as_string(keep_expr), inherit = TRUE)
  } else {
    keep_expr
  }
  selection <- if (is.character(keep_value)) {
    absent_keep <- setdiff(keep_value, data_names)
    if (length(absent_keep)) {
      cli::cli_abort("`keep` references missing column{?s} {.val {absent_keep}}.", call = call)
    }
    tidyselect::eval_select(rlang::expr(tidyselect::all_of(!!keep_value)), data = select_data)
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
#' Build a survey design from the annual sample and the declared cohort.
#' Use the result with srvyr, survey, and gtsummary.
#'
#' @details Hospital and stratum identifiers include the year. Hospital-years
#' without eligible discharges contribute zero to the domain calculation.
#' Filter the returned design to estimate within a smaller domain. For a
#' dataset saved with [nis_write_cohort()], omit `cohort`.
#'
#' @section Invalid design fields:
#' The design excludes discharges with missing, non-finite, or nonpositive
#' `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT`. Inspect the excluded counts
#' by field and year with [nis_design_report()].
#'
#' @section Adjusted charges and costs:
#' Keeping both the charge field and `CCR_NIS` adds `charges_adj` and
#' `cost_adj`. The default dollar year is the latest included design year.
#' Set `dollars` to use another reference year.
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
#' @param annualize Divide every discharge weight by the number of years with
#'   valid design records. Each partial year counts as one year.
#' @param dollars Reference dollar year for adjusted charges and costs.
#'   To set it, keep the charge field and `CCR_NIS`.
#' @param charges Name of the charge field. Defaults to `"TOTCHG"`.
#'   Choose the field for the years analyzed. See
#'   [Years and coding eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.html).
#'
#' @return A filtered `srvyr::tbl_svy` survey design. The analysis data contains
#'   the required design fields, the columns selected by `keep`, and any
#'   computed cost columns. [nis_label()] keeps binary indicators logical and
#'   converts known multi-level codes to factors. Use [stats::weights()] for the
#'   survey weights.
#' @family survey-design
#' @seealso [Make tables and fit survey models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html),
#'   [Make tables and fit survey models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html).
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
nis_design <- function(.data, cohort, keep, annualize = FALSE, dollars = NULL, charges = "TOTCHG") {
  call <- rlang::current_call()
  prepared <- nis_design_prepare(.data, rlang::enquo(cohort), rlang::enquo(keep), annualize, charges, call)
  nis_design_build(prepared$sample, prepared$fields, annualize, dollars, charges, call)
}

nis_design_prepare <- function(.data, cohort, keep, annualize, charges, call, inspect_quarters = annualize) {
  .data <- dplyr::ungroup(.data)
  saved <- !is.null(nis_saved_cohort(.data, call))
  cohort <- nis_cohort_membership(cohort, saved, call)
  nis_design_validate(.data, charges, annualize, call, saved)
  .data <- nis_design_input(.data)
  fields <- nis_design_fields(.data, keep, call)
  sample <- nis_design_sample(
    .data,
    cohort,
    fields$selected,
    fields$quarter_prototype,
    annualize,
    call,
    inspect_quarters,
    saved
  )
  sample$cohort <- nis_design_cohort_text(cohort)
  list(sample = sample, fields = fields)
}

nis_design_build <- function(sample, fields, annualize, dollars, charges, call) {
  hospital_rows <- sample$hospital_rows
  cohort_rows <- sample$cohort_rows
  no_cohort_years <- setdiff(sample$years, cohort_rows$YEAR)
  if (length(no_cohort_years) > 0L) {
    cli::cli_warn(c(
      "No cohort discharges in some sample years.",
      i = "Those years contribute only placeholder rows, but still count as a year for `annualize`."
    ))
  }

  year_count <- length(sample$years)
  divisor <- if (annualize) year_count else 1
  keys <- c("YEAR", "HOSP_NIS")
  hospital_index <- vctrs::vec_match(cohort_rows[keys], hospital_rows[keys])
  has_cohort <- tabulate(hospital_index, nrow(hospital_rows)) > 0L
  empty <- which(!has_cohort)
  if (!is.double(cohort_rows$DISCWT)) {
    cohort_rows$DISCWT <- as.double(cohort_rows$DISCWT)
  }
  discharge_weights <- cohort_rows$DISCWT

  prepared <- nis_design_records(cohort_rows, fields, dollars, charges, sample$years, call)
  layout <- nis_design_clusters(hospital_rows, hospital_index, empty, discharge_weights, divisor)
  design <- nis_cohort_design(
    prepared$rows,
    layout$structure,
    layout$placeholders,
    sample$excluded,
    prepared$cost_provenance,
    nest = layout$nest
  )
  attr(design, "nis_design_input") <- list(
    cohort = sample$cohort,
    years = sample$years,
    rows = sample$input_rows,
    divisor = divisor,
    annualize = annualize,
    reweighted = FALSE
  )
  design
}

nis_design_records <- function(cohort_rows, fields, dollars, charges, years, call) {
  has_cost_inputs <- all(c(charges, "CCR_NIS") %in% fields$keep_names)
  if (!is.null(dollars) && !has_cost_inputs) {
    cli::cli_abort("Keep both {.field {charges}} and `CCR_NIS` when requesting `dollars`.")
  }
  cohort_rows <- nis_label(cohort_rows)
  alias_sources <- cohort_rows[unique(fields$keep_names)]
  if (has_cost_inputs) {
    cost_fields <- c(charges, "CCR_NIS", "charges_adj", "cost_adj")
    charge_years <- unique(cohort_rows$YEAR)
    missing_charge_years <- charge_years[vapply(
      charge_years,
      function(year) {
        all(is.na(cohort_rows[[charges]][cohort_rows$YEAR == year]))
      },
      logical(1)
    )]
    if (length(missing_charge_years) > 0L) {
      cli::cli_warn(c(
        paste0(
          "`{charges}` is entirely missing in some cohort years; ",
          "adjusted costs and charges are `NA` there."
        ),
        i = "Name the right column with `charges`, or build one pooled column with `dplyr::mutate()` first."
      ))
    }
    if (is.null(dollars)) {
      dollars <- max(years)
    }
    cohort_rows <- nis_adjust_costs(cohort_rows, dollars, charges, call, cohort_years = years)
    cost_provenance <- nis_cost_provenance(cohort_rows)
  } else {
    cost_fields <- NULL
    cost_provenance <- NULL
  }

  cli::cli_inform("Preparing the cohort survey design.")
  cohort_rows <- nis_design_aliases(cohort_rows, fields, cost_fields, alias_sources, call)
  list(rows = cohort_rows, cost_provenance = cost_provenance)
}

nis_design_clusters <- function(hospital_rows, hospital_index, empty, discharge_weights, divisor) {
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
  list(structure = structure, placeholders = placeholders, nest = nest)
}

nis_design_cohort_text <- function(cohort) {
  paste(trimws(deparse(rlang::quo_get_expr(cohort), width.cutoff = 500L)), collapse = " ")
}
