#' Create a lazy whole-sample NIS survey design
#'
#' Estimate means, totals, and supported survey-weighted models in DuckDB.
#'
#' @details Use [dplyr::filter()] on the design to define a domain while
#' retaining the original sample for variance. Invalid design fields are
#' excluded when defining the sample.
#'
#' Use [survey::svymean()], [survey::svytotal()], and [survey::svyby()] for
#' summaries. [survey::svyglm()] supports additive Gaussian identity,
#' binomial and quasibinomial logit, and Poisson and quasipoisson log
#' models. Use [nis_design()] for interactions, offsets, survey quantiles,
#' chi-square tests, or `gtsummary::tbl_svysummary()`.
#'
#' The design supports the `"fail"` and `"adjust"` settings of
#' `survey.lonely.psu` and honors `survey.adjust.domain.lonely`.
#'
#' @param .data A lazy DuckDB query from [nis_open()].
#' @param weights A data-masked SQL-translatable expression for the analysis
#'   weights. The default uses discharge weights without annualization.
#' @return A lazy `nis_survey` design.
#' @family survey-design
#' @seealso [Analyze the whole sample in DuckDB](https://msaadasif.github.io/easyNIS/articles/whole-sample.html),
#'   [Analyze the whole sample in DuckDB](https://msaadasif.github.io/easyNIS/articles/whole-sample.html)
#' @export
#' @examples
#' nis <- nis_open(nis_example(2019:2020))
#' design <- nis_survey(nis)
#' older <- dplyr::filter(design, AGE >= 65)
#' survey::svymean(~LOS, older)
#' survey::svyby(~LOS, ~YEAR, older, survey::svymean)
nis_survey <- function(.data, weights = DISCWT) {
  if (
    !inherits(.data, "tbl_sql") ||
      !inherits(dbplyr::remote_con(.data), "nis_duckdb_connection") ||
      is.null(nis_open_source_paths(.data))
  ) {
    cli::cli_abort(c(
      "`.data` must be a DuckDB query from `nis_open()`.",
      i = "Use {.help easyNIS::nis_design} for in-memory data."
    ))
  }
  absent <- setdiff(.nis_design_fields, colnames(.data))
  if (length(absent)) {
    cli::cli_abort("Missing design field{?s} {.val {absent}}.")
  }
  if (!is.null(nis_saved_cohort(.data, rlang::current_call()))) {
    nis_survey_unsupported("Saved cohorts")
  }
  query <- dplyr::ungroup(.data)
  valid <- lapply(.nis_design_fields, nis_is_positive_finite_expr, data = query)
  query <- dplyr::filter(query, !!!valid)
  structure(
    list(query = query, weights = rlang::enquo(weights), domain = list()),
    class = c("nis_survey", "survey.design")
  )
}

#' @export
subset.nis_survey <- function(x, subset, ...) {
  nis_survey_no_dots(...)
  if (!missing(subset)) {
    x$domain <- c(x$domain, list(rlang::enquo(subset)))
  }
  x
}

#' @exportS3Method dplyr::filter
filter.nis_survey <- function(.data, ..., .by = NULL, .preserve = FALSE) {
  if (!is.null(rlang::get_expr(rlang::enquo(.by))) || !identical(.preserve, FALSE)) {
    nis_survey_unsupported("`.by` and `.preserve`")
  }
  .data$domain <- c(.data$domain, rlang::enquos(...))
  .data
}

# gtsummary first checks the survey.design class and then accesses $variables.
# Row-level survey methods also reach this field via model.frame().
#' @export
`$.nis_survey` <- function(x, name) {
  if (name %in% c("variables", "prob", "cluster", "strata", "fpc")) {
    nis_survey_unsupported("Access to row-level survey data")
  }
  .subset2(x, name)
}

#' @export
print.nis_survey <- function(x, ...) {
  cat(
    "Lazy NIS Taylor survey design\n",
    "PSUs: YEAR \u00d7 HOSP_NIS; strata: YEAR \u00d7 NIS_STRATUM (nested)\n",
    "Weights: ",
    rlang::as_label(x$weights),
    "\n",
    sep = ""
  )
  invisible(x)
}

#' @exportS3Method survey::svyquantile
svyquantile.nis_survey <- function(x, design, ...) {
  nis_survey_unsupported("`svyquantile()`")
}

#' @exportS3Method survey::svychisq
svychisq.nis_survey <- function(formula, design, ...) {
  nis_survey_unsupported("`svychisq()`")
}

nis_survey_unsupported <- function(feature) {
  cli::cli_abort(c(
    "{feature} is unsupported for a lazy survey analysis.",
    i = "Use {.help easyNIS::nis_design} for the row-level workflow."
  ))
}

nis_survey_no_dots <- function(...) {
  if (...length()) {
    nis_survey_unsupported("Additional arguments")
  }
}

nis_survey_policy <- function() {
  policy <- getOption("survey.lonely.psu", "fail")
  if (!identical(policy, "fail") && !identical(policy, "adjust")) {
    nis_survey_unsupported("This `survey.lonely.psu` setting")
  }
  policy
}

.nis_survey_keys <- c("YEAR", "NIS_STRATUM", "HOSP_NIS")

nis_survey_sql <- function(query) {
  paste0("(", dbplyr::sql_render(query), ")")
}

nis_survey_get <- function(design, sql) {
  nis_duckdb_translate_errors(DBI::dbGetQuery(dbplyr::remote_con(design$query), sql))
}

nis_survey_types <- function(design, query) {
  info <- nis_survey_get(design, paste("DESCRIBE SELECT * FROM", nis_survey_sql(query)))
  stats::setNames(info$column_type, info$column_name)
}

nis_survey_numeric <- function(x) {
  sprintf("nullif(CAST((%s) AS DOUBLE), 'NaN'::DOUBLE)", x)
}

nis_survey_project <- function(design, expressions) {
  query <- design$query
  domain <- stats::setNames(design$domain, paste0("in_domain", seq_along(design$domain), recycle0 = TRUE))
  expressions <- c(expressions, list(w = design$weights), domain)
  used <- unique(c(.nis_survey_keys, unlist(lapply(expressions, all.vars))))
  query <- dplyr::select(query, tidyselect::all_of(intersect(used, colnames(query))))
  types <- nis_survey_types(design, query)
  decimals <- setdiff(names(types)[startsWith(types, "DECIMAL(")], .nis_survey_keys)
  casts <- lapply(decimals, function(name) rlang::expr(as.double(!!rlang::sym(name))))
  query <- dplyr::mutate(query, !!!stats::setNames(casts, decimals))
  aliases <- nis_internal_names(query, colnames(query), paste0(".nis_svy_", seq_along(expressions)))
  projected <- dplyr::transmute(
    query,
    !!!rlang::syms(.nis_survey_keys),
    !!!stats::setNames(expressions, aliases)
  )
  projected <- dplyr::rename(projected, tidyselect::all_of(stats::setNames(aliases, names(expressions))))
  if (length(domain) && !all(nis_survey_types(design, projected)[names(domain)] %in% c("BOOLEAN", "NULL", '"NULL"'))) {
    cli::cli_abort("Survey domain expressions must be logical.")
  }
  inside <- if (length(domain)) Reduce(function(a, b) rlang::expr(!!a & !!b), rlang::syms(names(domain))) else TRUE
  dplyr::mutate(projected, inside = dplyr::coalesce(!!inside, FALSE))
}

nis_survey_formula <- function(formula) {
  if (!rlang::is_formula(formula, lhs = FALSE)) {
    nis_survey_unsupported("Inputs other than one-sided formulas")
  }
  variables <- as.list(attr(stats::terms(formula), "variables"))[-1L]
  if (!length(variables)) {
    nis_survey_unsupported("Formulas without variables")
  }
  variables
}

nis_survey_is_factor <- function(expr) {
  rlang::is_call(expr, "factor", n = 1L)
}

nis_survey_quos <- function(variables, formula) {
  lapply(variables, function(expr) {
    if (nis_survey_is_factor(expr) || rlang::is_call(expr, "I", n = 1L)) {
      expr <- expr[[2L]]
    }
    rlang::new_quosure(expr, environment(formula))
  })
}

#' @exportS3Method survey::degf
degf.nis_survey <- function(design, ...) {
  nis_survey_no_dots(...)
  if (!length(design$domain)) {
    roster <- nis_survey_roster(design)
    return(nrow(roster) - length(unique(roster$stratum)))
  }
  query <- nis_survey_project(design, list())
  keys <- paste(.nis_survey_keys, collapse = ", ")
  psus <- nis_survey_get(
    design,
    sprintf(
      "SELECT DISTINCT %s FROM %s WHERE inside",
      keys,
      nis_survey_sql(query)
    )
  )
  nrow(psus) - nrow(unique(psus[c("YEAR", "NIS_STRATUM")]))
}

nis_survey_roster <- function(design) {
  keys <- paste(.nis_survey_keys, collapse = ", ")
  roster <- nis_survey_get(design, sprintf("SELECT DISTINCT %s FROM %s", keys, nis_survey_sql(design$query)))
  if (!nrow(roster)) {
    cli::cli_abort("No discharges have valid design fields.")
  }
  if (anyDuplicated(roster[c("YEAR", "HOSP_NIS")])) {
    cli::cli_abort("Each hospital must map to one stratum within a year.")
  }
  nis_survey_roster_sizes(roster)
}

nis_survey_roster_sizes <- function(roster) {
  roster$stratum <- vctrs::vec_group_id(roster[c("YEAR", "NIS_STRATUM")])
  roster$n_psu <- tabulate(roster$stratum)[roster$stratum]
  roster
}

nis_survey_variance <- function(scores, psu, roster, lonely.psu = nis_survey_policy()) {
  strata <- roster$stratum[psu]
  survey::svyrecvar(
    scores,
    matrix(psu),
    matrix(strata),
    list(sampsize = matrix(roster$n_psu[psu]), popsize = NULL),
    lonely.psu = lonely.psu
  )
}
