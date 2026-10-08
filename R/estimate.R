#' Estimate an experimental scalar survey total, mean or proportion
#'
#' Uses native survey linearization after explicit outcome exclusion, retaining
#' full-design PSU information. The caller chooses the unadjusted hospital WR
#' variance policy and the degrees of freedom for a Wald interval. Scientific
#' approval, annual validation, and bounded proportion intervals remain pending.
#' No survey options or raw columns are changed. Current options must specify
#' `survey.lonely.psu = "fail"` and `survey.adjust.domain.lonely = FALSE`.
#'
#' @param design A [nis_survey_design()], [nis_pool_design()] or [nis_domain()]
#'   result using the experimental hospital WR method.
#' @param field Exact name of one retained numeric or logical outcome. BIGINT
#'   values convert through exact strings only when their absolute value is
#'   below 2^53. Factors, strings and other classed outcomes are refused.
#' @param statistic Explicitly choose `"total"`, `"mean"` or `"proportion"`.
#'   Proportions require observed values of zero or one.
#' @param missing Explicitly choose `"fail"` or `"exclude"` for NA and NaN.
#'   Infinite outcomes are always refused. Numeric sentinels retain raw meanings.
#' @param df Explicit positive numeric scalar or `Inf` for interval inference.
#'   Finite values use Student's t; `Inf` uses the normal distribution. Native
#'   domain and full-population degrees of freedom are reported separately.
#' @param confidence Explicit numeric scalar strictly between zero and one.
#' @param variance Must explicitly be `"wr_unadjusted"`.
#' @return A `nis_estimate` list with numeric scalar `estimate`, `se`, `df`,
#'   `confidence`, `lower`, `upper`, `statistic`, and `estimand`; the original
#'   native `svystat` in `native`; the outcome-subset native `design` with raw
#'   retained columns; `sample` accounting; and complete design `provenance`.
#'   Empty analyses and nonfinite results are refused. Zero estimates and SEs
#'   are valid. Wald intervals are not clipped to outcome bounds. Pooled totals
#'   respect constructor intent; pooled means and proportions are weighted over
#'   included discharges, not arithmetic averages of annual means/proportions.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$domain <- core$HOSP_NIS %in% c("0001", "0003")
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   data <- nis_import(session, path, 2022)
#'   design <- nis_survey_design(data, c("LOS", "domain"),
#'     TRUE, "hospital_wr", "fail")
#'   domain <- nis_domain(design, "domain", "fail")
#'   result <- nis_estimate(domain, "LOS", "total", "fail",
#'     df = 2, confidence = 0.95, variance = "wr_unadjusted")
#'   result[c("estimate", "se", "lower", "upper")]
#'   nis_close(session)
#'   unlink(path)
#' }
nis_estimate <- function(design, field, statistic, missing, df, confidence, variance) {
  if (!inherits(design, "nis_survey") ||
      !identical(design$provenance$method, "hospital_wr") ||
      !identical(design$provenance$singleton, "fail")) {
    stop("`design` must be an experimental hospital WR nis_survey result.", call. = FALSE)
  }
  check_string(field, "field")
  if (!field %in% names(design$design$variables)) {
    stop("Outcome field was not retained in the design.", call. = FALSE)
  }
  if (base::missing(statistic) || base::missing(missing) || base::missing(variance) ||
      base::missing(df) || base::missing(confidence)) {
    stop("Choose explicit `statistic`, `missing`, `df`, `confidence` and `variance` policies.",
         call. = FALSE)
  }
  check_string(statistic, "statistic")
  check_string(missing, "missing")
  check_string(variance, "variance")
  if (!statistic %in% c("total", "mean", "proportion") ||
      !missing %in% c("fail", "exclude") || variance != "wr_unadjusted") {
    stop("Choose total/mean/proportion, fail/exclude and variance = \"wr_unadjusted\".",
         call. = FALSE)
  }
  if (!is.numeric(df) || is.complex(df) || is.object(df) || length(df) != 1L || is.na(df) || df <= 0) {
    stop("`df` must be a positive numeric scalar or Inf.", call. = FALSE)
  }
  if (!is.numeric(confidence) || is.complex(confidence) || is.object(confidence) || length(confidence) != 1L ||
      is.na(confidence) || confidence <= 0 || confidence >= 1) {
    stop("`confidence` must be a numeric scalar strictly between zero and one.", call. = FALSE)
  }
  if (!identical(getOption("survey.lonely.psu"), "fail") ||
      !identical(getOption("survey.adjust.domain.lonely"), FALSE)) {
    stop(paste0("wr_unadjusted requires current survey.lonely.psu = \"fail\" and ",
                "survey.adjust.domain.lonely = FALSE; easyNIS does not alter options."),
         call. = FALSE)
  }
  pooled <- identical(design$provenance$scope, "experimental_pooled_years")
  if (pooled && statistic == "total" && design$provenance$estimand == "pooled_proportion") {
    stop("A total is incompatible with pooled_proportion intent.", call. = FALSE)
  }
  outcome <- design$design$variables[[field]]
  if (inherits(outcome, "integer64")) {
    outcome <- as.double(as.character(outcome))
    if (any(abs(outcome) >= 2^53, na.rm = TRUE)) {
      stop("BIGINT outcomes exceed the exact double range.", call. = FALSE)
    }
  } else if ((!is.numeric(outcome) && !is.logical(outcome)) || is.complex(outcome) || is.object(outcome)) {
    stop("Outcomes must be plain numeric or logical vectors, or safe BIGINT values.", call. = FALSE)
  }
  if (!is.null(dim(outcome))) stop("Outcomes must be single vectors.", call. = FALSE)
  if (any(is.infinite(outcome))) stop("Infinite outcomes are unsupported.", call. = FALSE)
  keep <- !is.na(outcome)
  if (missing == "fail" && any(!keep)) {
    stop("Outcome contains NA or NaN; choose explicit exclusion or resolve missingness.", call. = FALSE)
  }
  if (!any(keep)) stop("Cannot estimate an empty analysis.", call. = FALSE)
  if (statistic == "proportion" && any(!outcome[keep] %in% c(0, 1))) {
    stop("Proportions require observed zero/one outcomes.", call. = FALSE)
  }
  native_design <- if (all(keep)) design$design else design$design[keep, ]
  denominator <- sum(stats::weights(native_design))
  if (!is.finite(denominator) || denominator <= 0) {
    stop("Analysis weight denominator must remain finite and positive.", call. = FALSE)
  }
  x <- matrix(as.double(outcome[keep]), ncol = 1L, dimnames = list(NULL, field))
  current_options <- options()[grepl("^survey[.]", names(options()))]
  native <- if (statistic == "total") survey::svytotal(x, native_design) else
    survey::svymean(x, native_design)
  estimate <- unname(as.double(stats::coef(native)))
  se <- unname(as.double(survey::SE(native)))
  if (length(estimate) != 1L || length(se) != 1L ||
      !is.finite(estimate) || !is.finite(se) || se < 0) {
    stop("Native estimation did not return a finite scalar estimate and SE.", call. = FALSE)
  }
  # Upper-tail quantiles avoid rounding (1 + confidence) / 2 to one.
  critical <- if (is.infinite(df)) stats::qnorm((1 - confidence) / 2, lower.tail = FALSE) else
    stats::qt((1 - confidence) / 2, df, lower.tail = FALSE)
  bounds <- if (se == 0) rep(estimate, 2L) else estimate + c(-1, 1) * critical * se
  if (any(!is.finite(bounds))) stop("Wald interval bounds are nonfinite.", call. = FALSE)
  estimand <- if (pooled && statistic == "total") design$provenance$estimand else
    if (pooled) paste0("weighted_pooled_", statistic) else paste0("single_year_", statistic)
  structure(list(estimate = estimate, se = se, df = as.double(df),
    confidence = as.double(confidence), lower = bounds[1L], upper = bounds[2L],
    statistic = statistic, estimand = estimand, native = native, design = native_design,
    sample = list(supplied = length(outcome), included = sum(keep),
      excluded_missing = sum(!keep), weighted_denominator = denominator,
      domain_degrees_of_freedom = survey::degf(design$design),
      analysis_degrees_of_freedom = survey::degf(native_design),
      full_population_degrees_of_freedom = design$population$degrees_of_freedom),
    provenance = list(field = field, statistic = statistic, missing = missing,
      variance = variance, df = as.double(df), confidence = as.double(confidence),
      interval = if (is.infinite(df)) "normal_wald" else "t_wald",
      survey_version = as.character(utils::packageVersion("survey")),
      current_survey_options = current_options, design = design$provenance,
      population = design$population, domains = design$domains,
      scope = "experimental_scalar_inference", analysis_ready = FALSE)), class = "nis_estimate")
}
