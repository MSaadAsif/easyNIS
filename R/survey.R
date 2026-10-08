#' Prepare an experimental single-year survey design
#'
#' Collects only structural fields and explicitly requested analysis columns,
#' retaining every supplied discharge before domain selection. This is an eager
#' in-memory prototype, not a benchmarked large-data method. The caller must
#' declare a complete population and explicitly choose the hospital-cluster
#' with-replacement method and rejection of singleton strata. These declarations
#' do not authenticate annual layouts, conversion history or prefiltering.
#' No finite-population correction or weight scaling occurs. easyNIS does not
#' set survey options. Loading `survey` for the first time initializes that
#' package's own defaults; pre-existing caller options remain in force.
#'
#' @param data A relation returned by [nis_import()], [nis_flag_codes()] or
#'   [nis_select()], retaining all structural fields.
#' @param columns Non-empty unique exact names of analysis columns to retain.
#' @param full_population Must explicitly be `TRUE`, declaring that the supplied
#'   relation contains the complete annual sample. This remains unverified.
#' @param method Must explicitly be `"hospital_wr"`. Other designs and pooling
#'   are not implemented.
#' @param singleton Must explicitly be `"fail"`. Strata with fewer than two
#'   distinct hospitals are rejected; alternative policies require review.
#' @return A `nis_survey` list with native `survey` `design`, full-population
#'   aggregate `population` accounting, `provenance`, and a `domains` history.
#'   `analysis_ready` remains `FALSE`. Raw analysis columns and missing outcomes
#'   are retained. BIGINT weights are converted to exact doubles only below
#'   2^53; larger integer weights and nonfinite reciprocal weights are refused.
#'   Initial survey options are recorded. Native inference uses current options;
#'   this constructor does not approve their choices or subsequent estimates.
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
#'   stays <- nis_import(session, path, 2022)
#'   design <- nis_survey_design(stays, c("LOS", "domain"),
#'     full_population = TRUE, method = "hospital_wr", singleton = "fail")
#'   domain <- nis_domain(design, "domain", missing = "fail")
#'   domain$population
#'   survey::svytotal(~LOS, domain$design)
#'   nis_close(session)
#'   unlink(path)
#' }
nis_survey_design <- function(data, columns, full_population, method, singleton) {
  check_relation(data)
  if (base::missing(full_population) || !identical(full_population, TRUE)) {
    stop("Explicitly declare `full_population = TRUE`; prefiltered inputs are unsupported.",
         call. = FALSE)
  }
  if (base::missing(method) || !identical(method, "hospital_wr")) {
    stop("Explicitly choose `method = \"hospital_wr\"`; other designs are unsupported.",
         call. = FALSE)
  }
  if (base::missing(singleton) || !identical(singleton, "fail")) {
    stop("Explicitly choose `singleton = \"fail\"`; other policies are unsupported.",
         call. = FALSE)
  }
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("Install the optional `survey` package to prepare a design.", call. = FALSE)
  }
  check_projection(data, columns)
  required <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
  require_fields(data$schema, required, "survey relation")
  report <- nis_validate(data)
  if (report$structural_errors) {
    stop("Survey preparation requires structurally valid input; inspect nis_validate().",
         call. = FALSE)
  }
  rows <- nis_collect(data, unique(c(required, columns)))
  if (anyNA(rows$YEAR) || any(rows$YEAR != data$year)) {
    stop("Survey preparation requires one consistent supplied year.", call. = FALSE)
  }
  weights <- rows$DISCWT
  if (inherits(weights, "integer64")) {
    weights <- as.double(as.character(weights))
    if (any(weights >= 2^53)) {
      stop("BIGINT weights exceed the exact double range; use a reviewed conversion.", call. = FALSE)
    }
  }
  weights <- as.double(weights)
  if (any(!is.finite(1 / weights))) {
    stop("Weights are too small for finite native survey probabilities.", call. = FALSE)
  }
  hospital <- as.character(rows$HOSP_NIS)
  stratum <- as.character(rows$NIS_STRATUM)
  pairs <- unique(data.frame(hospital = hospital, stratum = stratum,
                             stringsAsFactors = FALSE))
  if (anyDuplicated(pairs$hospital)) {
    stop("A hospital occurs in multiple strata; review the supplied mapping.", call. = FALSE)
  }
  hospitals_per_stratum <- table(pairs$stratum)
  if (any(hospitals_per_stratum < 2L)) {
    stop("Singleton strata are unsupported by the explicit fail policy.", call. = FALSE)
  }
  native <- survey::svydesign(ids = data.frame(hospital = hospital),
    strata = data.frame(stratum = stratum), weights = weights,
    data = rows, nest = TRUE)
  structure(list(
    design = native,
    population = list(discharges = nrow(rows), hospitals = nrow(pairs),
      strata = length(hospitals_per_stratum),
      degrees_of_freedom = survey::degf(native), singleton_strata = 0L),
    provenance = list(year = data$year, method = method, singleton = singleton,
      full_population = "caller_declared_unverified", finite_population_correction = "none",
      weight_scaling = "none", columns = names(rows),
      relation_provenance = data$provenance, flags = data$flags,
      sources = data$sources, component_schemas = data$component_schemas,
      selections = data$selections, joins = data$joins,
      scope = "experimental_single_year", analysis_ready = FALSE,
      survey_version = as.character(utils::packageVersion("survey")),
      initial_survey_options = options()[grepl("^survey[.]", names(options()))]),
    domains = list()
  ), class = "nis_survey")
}

#' Select an experimental domain after constructing the full design
#'
#' Uses native survey-design subsetting to retain the original PSU information,
#' including hospitals without domain members. No design is rebuilt from the
#' selected rows. Full-population accounting remains available independently
#' from each domain's included, excluded and unknown discharge counts.
#'
#' @param design A result of [nis_survey_design()] or [nis_domain()].
#' @param field Exact name of a retained logical domain column. Numeric 0/1
#'   vectors are refused; declare a logical indicator explicitly.
#' @param missing Explicitly choose `"fail"` to reject unknown indicators or
#'   `"exclude"` to exclude them and record their count.
#' @return A new `nis_survey` with the native domain `design` and appended
#'   `domains` history. Empty domains are retained; they do not justify inference.
#'   Inference policies, outcome exclusions, and annual approval remain pending.
#' @inherit nis_survey_design examples
#' @export
nis_domain <- function(design, field, missing) {
  if (!inherits(design, "nis_survey")) {
    stop("`design` must come from nis_survey_design().", call. = FALSE)
  }
  check_string(field, "field")
  if (!field %in% names(design$design$variables)) {
    stop("Domain field was not retained in the design.", call. = FALSE)
  }
  if (base::missing(missing)) stop("Choose an explicit domain `missing` policy.", call. = FALSE)
  check_string(missing, "missing")
  missing <- match.arg(missing, c("fail", "exclude"))
  indicator <- design$design$variables[[field]]
  if (!is.logical(indicator)) {
    stop("Domain indicators must be logical; numeric coding is not inferred.", call. = FALSE)
  }
  unknown <- sum(is.na(indicator))
  if (missing == "fail" && unknown > 0L) {
    stop("Domain indicators contain unknown values; explicitly choose exclusion or resolve them.",
         call. = FALSE)
  }
  keep <- !is.na(indicator) & indicator
  result <- design
  result$design <- design$design[keep, ]
  result$domains <- c(design$domains, list(list(field = field, missing = missing,
    supplied = length(indicator), included = sum(keep),
    excluded_false = sum(!indicator, na.rm = TRUE), unknown = unknown)))
  result
}
