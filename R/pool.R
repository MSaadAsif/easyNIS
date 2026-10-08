#' Pool complete experimental single-year designs with an explicit estimand
#'
#' Creates year-specific hospital and stratum keys before native survey
#' construction, so reused annual identifiers cannot merge across years.
#' Combined totals and pooled proportions retain annual weights. Average annual
#' totals explicitly divide native weights by the number of supplied years.
#' This is the average over supplied years, not an assertion of contiguous or
#' complete historical coverage. A pooled proportion is weighted across supplied
#' discharges, not the arithmetic average of annual proportions.
#'
#' @param designs A list of at least two complete [nis_survey_design()] results
#'   with distinct years. Previously selected domains and pooled inputs are refused.
#' @param columns Non-empty unique exact analysis columns present in every design.
#'   Their classes and factor levels must agree across years. Raw identifiers
#'   in the pooled projection become exact strings; annual designs retain raw types.
#' @param estimand Explicitly choose `"combined_total"`,
#'   `"average_annual_total"`, or `"pooled_proportion"`.
#' @return A `nis_survey` with native `design`, pooled `population` accounting,
#'   explicit `provenance`, empty `domains`, and `annual_designs` retaining the
#'   originals. Use [nis_domain()] after pooling. Native calls remain the caller's
#'   responsibility; the declared intent does not restrict arbitrary native calls.
#'   This eager prototype does not approve annual mappings, year composition,
#'   historical/trend weights or downstream scientific inference.
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   paths <- character()
#'   designs <- lapply(2021:2022, function(year) {
#'     core <- nis_synthetic_data(year)$core
#'     path <- tempfile(fileext = ".parquet")
#'     paths <<- c(paths, path)
#'     DBI::dbWriteTable(session$connection, paste0("invented_", year), core)
#'     DBI::dbExecute(session$connection, paste0("COPY invented_", year, " TO ",
#'       DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'     data <- nis_import(session, path, year)
#'     nis_survey_design(data, "LOS", TRUE, "hospital_wr", "fail")
#'   })
#'   combined <- nis_pool_design(designs, "LOS", "combined_total")
#'   average <- nis_pool_design(designs, "LOS", "average_annual_total")
#'   survey::svytotal(~LOS, combined$design)
#'   survey::svytotal(~LOS, average$design)
#'   nis_close(session)
#'   unlink(paths)
#' }
#' @export
nis_pool_design <- function(designs, columns, estimand) {
  if (!is.list(designs) || length(designs) < 2L ||
      !all(vapply(designs, inherits, logical(1), "nis_survey"))) {
    stop("`designs` must contain at least two complete single-year nis_survey results.",
         call. = FALSE)
  }
  for (design in designs) {
    if (!identical(design$provenance$scope, "experimental_single_year") ||
        length(design$domains) || !identical(design$provenance$method, "hospital_wr") ||
        !identical(design$provenance$singleton, "fail")) {
      stop("Pool complete single-year hospital WR designs before selecting domains.", call. = FALSE)
    }
  }
  years <- vapply(designs, function(design) design$provenance$year, numeric(1))
  if (anyDuplicated(years)) stop("Each supplied design must have a distinct year.", call. = FALSE)
  if (!is.character(columns) || !length(columns) || anyNA(columns) ||
      any(!nzchar(columns)) || anyDuplicated(columns)) {
    stop("`columns` must be unique non-empty column names.", call. = FALSE)
  }
  if (base::missing(estimand)) stop("Choose an explicit pooled `estimand`.", call. = FALSE)
  check_string(estimand, "estimand")
  estimand <- match.arg(estimand, c("combined_total", "average_annual_total", "pooled_proportion"))
  fields <- unique(c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", columns))
  identifier_fields <- c("KEY_NIS", "HOSP_NIS", "NIS_STRATUM")
  annual_rows <- lapply(designs, function(design) {
    rows <- design$design$variables
    if (!all(fields %in% names(rows))) {
      stop("Requested structural or analysis fields must be present in every annual design.",
           call. = FALSE)
    }
    rows <- rows[, fields, drop = FALSE]
    for (field in identifier_fields) rows[[field]] <- as.character(rows[[field]])
    rows
  })
  for (field in setdiff(fields, identifier_fields)) {
    reference <- class(annual_rows[[1L]][[field]])
    if (!all(vapply(annual_rows, function(rows) identical(class(rows[[field]]), reference), logical(1)))) {
      stop("Pooled field classes differ; use reviewed explicit annual transformations.", call. = FALSE)
    }
    if (is.factor(annual_rows[[1L]][[field]]) &&
        !all(vapply(annual_rows, function(rows) identical(levels(rows[[field]]),
          levels(annual_rows[[1L]][[field]])), logical(1)))) {
      stop("Pooled factor levels differ; use reviewed explicit annual transformations.", call. = FALSE)
    }
  }
  rows <- do.call(rbind, annual_rows)
  rownames(rows) <- NULL
  weights <- unlist(lapply(designs, function(design) as.double(stats::weights(design$design))),
                    use.names = FALSE)
  divisor <- if (estimand == "average_annual_total") length(years) else 1L
  weights <- weights / divisor
  if (any(!is.finite(weights)) || any(weights <= 0) || any(!is.finite(1 / weights))) {
    stop("Pooled weights and native probabilities must remain finite and positive.", call. = FALSE)
  }
  # Previously validated identifiers and years contain digits only. The separator
  # makes these compound keys unambiguous while retaining exact source strings.
  hospital <- paste(rows$YEAR, rows$HOSP_NIS, sep = ":")
  stratum <- paste(rows$YEAR, rows$NIS_STRATUM, sep = ":")
  native <- survey::svydesign(ids = data.frame(hospital = hospital),
    strata = data.frame(stratum = stratum), weights = weights, data = rows, nest = TRUE)
  structure(list(
    design = native,
    population = list(discharges = nrow(rows), hospitals = length(unique(hospital)),
      strata = length(unique(stratum)), degrees_of_freedom = survey::degf(native),
      singleton_strata = 0L),
    provenance = list(years = as.integer(years), estimand = estimand,
      method = "hospital_wr", singleton = "fail", full_population = "caller_declared_unverified",
      finite_population_correction = "none", weight_divisor = divisor,
      columns = names(rows), identifier_projection = "exact_strings_with_year_specific_design_keys",
      annual_provenance = lapply(designs, function(design) design$provenance),
      scope = "experimental_pooled_years", analysis_ready = FALSE,
      survey_version = as.character(utils::packageVersion("survey")),
      initial_survey_options = options()[grepl("^survey[.]", names(options()))]),
    domains = list(), annual_designs = designs
  ), class = "nis_survey")
}
