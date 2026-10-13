#' Declare an analysis factor while preserving its raw source field
#'
#' Adds a distinct unordered factor column to an experimental survey design.
#' The caller supplies every allowed raw level and its one-to-one label in
#' the desired order. Unknown observed values reject the call; source NA/NaN
#' remain missing. This is an analysis declaration, not an annual codebook.
#'
#' @param design An experimental [nis_survey_design()], [nis_pool_design()] or
#'   [nis_domain()] result.
#' @param field Exact retained source field name. Plain numeric, logical or
#'   character vectors are accepted; classed values, matrices and infinities
#'   are refused. BIGINT identifiers require a separate exact conversion.
#' @param name New analysis field name, distinct from all retained columns
#'   without regard to case. Native reserved model field names are refused.
#' @param levels Nonempty unique, nonmissing plain raw values of the same
#'   kind as the source (numeric, logical or character), in declared order.
#'   Unobserved declared levels are retained. Numeric values match directly,
#'   without formatting or conversion through character labels.
#' @param labels Explicit unique, nonblank plain character labels, one per
#'   raw level. No clinical meanings or missing-code labels are inferred.
#' @return A new `nis_survey` with the added factor and an appended
#'   `provenance$analysis_transforms` declaration. Raw source values, other
#'   columns, rows, native design information, population and domain history
#'   are unchanged. `provenance$columns` includes the new analysis field and
#'   `analysis_ready` remains FALSE. Mapping status is caller-declared/unverified.
#'   Level order is declared; no contrast scheme is set or universal fitted
#'   reference group promised. Inspect each fitted model's actual factor coding
#'   and support diagnostics, especially after complete-case exclusions.
#'   An undeclared observed value raises `nis_factor_error` with `field` and
#'   aggregate `affected` count; no record values or partial result are returned.
#' @export
#' @examples
#' if (requireNamespace("survey", quietly = TRUE)) {
#'   session <- nis_open()
#'   path <- tempfile(fileext = ".parquet")
#'   core <- nis_synthetic_data()$core
#'   core$group <- rep(c(0, 1), length.out = nrow(core))
#'   DBI::dbWriteTable(session$connection, "invented", core)
#'   DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'     DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#'   design <- nis_survey_design(nis_import(session, path, 2022), c("group", "LOS"),
#'     TRUE, "hospital_wr", "fail")
#'   analysis <- nis_factor(design, "group", "group_factor", c(0, 1),
#'     c("Comparator", "Exposed"))
#'   fit <- nis_model(analysis, LOS ~ group_factor, "gaussian", "exclude",
#'     2, 0.95, "wr_unadjusted")
#'   fit$factors
#'   nis_close(session)
#'   unlink(path)
#' }
nis_factor <- function(design, field, name, levels, labels) {
  if (!inherits(design, "nis_survey") || !is.data.frame(design$design$variables)) {
    stop("`design` must be an experimental nis_survey result.", call. = FALSE)
  }
  check_string(field, "field")
  check_string(name, "name")
  rows <- design$design$variables
  if (!field %in% names(rows)) stop("Factor source field was not retained in the design.", call. = FALSE)
  if (!nzchar(trimws(name)) || tolower(name) %in% tolower(c(names(rows),
      ".survey.prob.weights", "(weights)", "(offset)"))) {
    stop("Choose a new nonblank factor name without retained-field or native reserved-name conflicts.", call. = FALSE)
  }
  kind <- function(x) {
    if (is.object(x) || !is.null(dim(x)) || is.complex(x)) return(NA_character_)
    if (is.numeric(x) && all(is.na(x) | is.finite(x))) return("numeric")
    if (is.logical(x)) return("logical")
    if (is.character(x)) return("character")
    NA_character_
  }
  source <- rows[[field]]
  if (is.na(kind(source))) {
    stop("Factor sources must be plain finite numeric, logical or character vectors.", call. = FALSE)
  }
  if (base::missing(levels) || base::missing(labels)) {
    stop("Declare explicit raw levels and their labels.", call. = FALSE)
  }
  if (!length(levels) || is.na(kind(levels)) || kind(levels) != kind(source) ||
      anyNA(levels) || anyDuplicated(levels)) {
    stop("Raw levels must be unique nonmissing plain values of the same kind as the source.", call. = FALSE)
  }
  if (!is.character(labels) || is.object(labels) || !is.null(dim(labels)) ||
      length(labels) != length(levels) || anyNA(labels) ||
      any(!nzchar(trimws(labels))) || anyDuplicated(labels)) {
    stop("Supply one unique nonblank plain character label per raw level.", call. = FALSE)
  }
  codes <- match(source, levels)
  affected <- sum(!is.na(source) & is.na(codes))
  if (affected > 0L) {
    stop(structure(list(message = paste0("Factor source '", field, "' has ", affected,
      " undeclared observed values; declare their levels explicitly."), call = NULL,
      field = field, affected = affected), class = c("nis_factor_error", "error", "condition")))
  }
  result <- design
  result$design$variables[[name]] <- structure(codes, levels = unname(labels), class = "factor")
  declaration <- list(type = "factor", field = field, name = name,
    levels = unname(levels), labels = unname(labels), raw_preserved = TRUE,
    mapping_status = "caller_declared_unverified")
  result$provenance$analysis_transforms <- c(design$provenance$analysis_transforms, list(declaration))
  result$provenance$columns <- names(result$design$variables)
  result$provenance$analysis_ready <- FALSE
  result
}
