#' Assemble an experimental numeric regression table
#'
#' Selects existing coefficient inference from one [nis_model()] result. This
#' function performs no fit or new inference. Coefficients remain on the model's
#' link scale, including transformed outcomes and exposure-offset models.
#'
#' @param model An experimental [nis_model()] result.
#' @param specification A nonempty plain data frame with exactly plain
#'   character columns `id`, `term`, `label` and `unit`, in any order. IDs must
#'   be unique. Terms must exactly match coefficient names and may repeat.
#' @param scale Explicitly choose `"link"`. No other scale is supported.
#' @return A `nis_regression_table` list containing declaration and existing
#'   numeric coefficient columns in `data`, plus the original model, factors,
#'   sample, diagnostics and provenance. Aliases and undefined inference retain
#'   their original `NA`/`NaN` values. Disclosure remains unreviewed.
#' @details Labels and units are caller declarations. They do not authenticate
#'   reference groups or imply odds, means or rates. Intervals are pointwise;
#'   tests remain existing link-scale null-zero tests. Existing native weighted
#'   inference is preserved separately from raw sample counts. No rounding,
#'   exponentiation or reference-row inference occurs. Annual support and
#'   scientific approval remain pending.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$x <- rep(c(-2, -1, 1), 4L) + rep(c(-0.4, 0.2, 0.6, -0.3), each = 3L)
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), c("LOS", "x"),
#'     TRUE, "hospital_wr", "fail")
#'   fit <- nis_model(design, LOS ~ x, "gaussian", "fail", 2, 0.95, "wr_unadjusted")
#'   spec <- data.frame(id = c("slope", "constant"),
#'     term = c("x", "(Intercept)"), label = c("LOS slope", "Constant"),
#'     unit = c("days", "days"))
#'   nis_regression_table(fit, spec, "link")$data
#'   nis_close(session)
#'   unlink(path)
#' }
nis_regression_table <- function(model, specification, scale) {
  if (!inherits(model, "nis_model") || !inherits(model$native, "svyglm")) {
    stop("`model` must be a nis_model result.", call. = FALSE)
  }
  if (missing(scale)) stop("Choose the explicit `link` coefficient scale.", call. = FALSE)
  check_string(scale, "scale")
  if (!identical(scale, "link")) stop("Only scale = \"link\" is supported.", call. = FALSE)
  expected <- c("id", "term", "label", "unit")
  if (!is.data.frame(specification) || !identical(class(specification), "data.frame") ||
      nrow(specification) < 1L || length(names(specification)) != 4L ||
      anyDuplicated(names(specification)) || !setequal(names(specification), expected)) {
    stop("`specification` must be a nonempty plain data frame with exactly id, term, label and unit columns.", call. = FALSE)
  }
  specification <- specification[, expected, drop = FALSE]
  valid <- vapply(specification, function(x) is.character(x) && is.null(dim(x)) &&
    !is.object(x) && length(x) == nrow(specification), logical(1))
  if (!all(valid) || anyNA(as.matrix(specification)) || any(!nzchar(as.matrix(specification)))) {
    stop("Every specification column must contain nonmissing, nonempty plain character values.", call. = FALSE)
  }
  if (anyDuplicated(specification$id)) stop("Specification `id` values must be unique.", call. = FALSE)
  coefficients <- model$coefficients
  if (!is.data.frame(coefficients) || !all(c("term", "estimate", "se", "statistic", "p_value", "lower", "upper", "aliased") %in% names(coefficients))) {
    stop("`model` does not contain the expected coefficient inference.", call. = FALSE)
  }
  if (any(!specification$term %in% coefficients$term)) {
    stop("Every specification term must exactly match a fitted coefficient name.", call. = FALSE)
  }
  at <- match(specification$term, coefficients$term)
  values <- coefficients[at, c("estimate", "se", "statistic", "p_value", "lower", "upper", "aliased"), drop = FALSE]
  rownames(values) <- NULL
  data <- specification
  for (name in names(values)) data[[name]] <- values[[name]]
  data$coefficient_scale <- rep("link", nrow(data))
  data$family <- rep(model$provenance$family, nrow(data))
  data$link <- rep(model$provenance$link, nrow(data))
  data$df <- rep(model$provenance$df, nrow(data))
  data$confidence <- rep(model$provenance$confidence, nrow(data))
  data$raw_supplied <- rep(as.double(model$sample$supplied), nrow(data))
  data$raw_included <- rep(as.double(model$sample$included), nrow(data))
  data$raw_missing <- rep(as.double(model$sample$excluded_missing), nrow(data))
  data$weighted_denominator <- rep(model$sample$weighted_denominator, nrow(data))
  data$analysis_hospitals <- rep(as.double(length(unique(model$design$cluster[[1L]]))), nrow(data))
  data$disclosure_status <- rep("unreviewed", nrow(data))
  rownames(data) <- NULL
  provenance <- list(declarations = specification, scale = "link",
    interval_scope = "pointwise", model = model$provenance,
    scope = "experimental_numeric_regression_table", analysis_ready = FALSE)
  structure(list(data = data, model = model, factors = model$factors,
    sample = model$sample, diagnostics = model$diagnostics, provenance = provenance),
    class = "nis_regression_table")
}
