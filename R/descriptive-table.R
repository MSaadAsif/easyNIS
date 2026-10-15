#' Calculate an experimental numeric descriptive table
#'
#' Each declared row delegates to [nis_estimate()] on the supplied experimental
#' design. Missingness applies to each field independently. The result retains
#' the original estimates and their design provenance. Values are numeric and
#' unrounded; disclosure review and annual scientific validation remain pending.
#'
#' @param design An experimental [nis_survey_design()], [nis_pool_design()] or
#'   [nis_domain()] result.
#' @param specification A nonempty plain data frame with character columns
#'   `id`, `field`, `statistic`, `label` and `unit`. IDs must be unique. Rows
#'   retain their order, and exact field names may repeat.
#' @param missing Explicitly choose `"fail"` or `"exclude"` for missing outcomes,
#'   applying the policy separately to each declared field.
#' @param df Positive numeric scalar or `Inf` for pointwise Wald intervals.
#' @param confidence Numeric scalar strictly between zero and one.
#' @param variance Explicitly choose `"wr_unadjusted"`.
#' @return A `nis_descriptive_table` list with declaration columns and numeric
#'   `data`, unchanged row-wise `nis_estimate` objects in `results`, and
#'   `provenance`. The table includes `estimand`, `weighted_estimate`, `se`,
#'   `lower`, `upper`, `df`, `confidence`, `raw_supplied`, `raw_included`,
#'   `raw_missing`, `weighted_denominator`, `analysis_hospitals`, and
#'   `disclosure_status`. Hospital counts use distinct native first-level
#'   cluster IDs among included observations. `analysis_ready` is always FALSE.
#'   If any row fails, the call errors without returning a partial table.
#' @param by Optional exact retained standard factor field. Group rows follow
#'   its observed factor-level order; unused declared levels produce no rows.
#' @param group_missing With `by`, explicitly choose `"fail"` or `"exclude"`
#'   for missing group membership. This policy is required only when grouping.
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
#'   design <- nis_survey_design(data, c("LOS", "domain"), TRUE,
#'     "hospital_wr", "fail")
#'   specification <- data.frame(id = c("los", "domain"),
#'     field = c("LOS", "domain"), statistic = c("mean", "proportion"),
#'     label = c("Length of stay", "Domain share"),
#'     unit = c("days", "proportion"))
#'   table <- nis_descriptive_table(design, specification, "fail", 2,
#'     0.95, "wr_unadjusted")
#'   table$data
#'   nis_close(session)
#'   unlink(path)
#' }
nis_descriptive_table <- function(design, specification, missing, df, confidence, variance,
                                  by = NULL, group_missing = NULL) {
  if (base::missing(missing) || base::missing(df) || base::missing(confidence) ||
      base::missing(variance)) {
    stop("Choose explicit `missing`, `df`, `confidence` and `variance` policies.",
         call. = FALSE)
  }
  if (!is.data.frame(specification) || !identical(class(specification), "data.frame") ||
      nrow(specification) < 1L || length(names(specification)) != 5L ||
      anyDuplicated(names(specification)) ||
      !setequal(names(specification), c("id", "field", "statistic", "label", "unit"))) {
    stop("`specification` must be a nonempty plain data frame with exactly id, field, statistic, label and unit columns.",
         call. = FALSE)
  }
  specification <- specification[, c("id", "field", "statistic", "label", "unit"), drop = FALSE]
  valid_column <- vapply(specification, function(x) is.character(x) && is.null(dim(x)) &&
    !is.object(x) && length(x) == nrow(specification), logical(1))
  if (!all(valid_column) || anyNA(as.matrix(specification)) ||
      any(!nzchar(as.matrix(specification)))) {
    stop("Every specification column must contain nonmissing, nonempty plain character values.",
         call. = FALSE)
  }
  if (anyDuplicated(specification$id)) {
    stop("Specification `id` values must be unique.", call. = FALSE)
  }
  if (any(!specification$statistic %in% c("mean", "proportion", "total"))) {
    stop("Specification statistics must be mean, proportion or total.", call. = FALSE)
  }
  if (any(specification$statistic == "proportion" & specification$unit != "proportion")) {
    stop("Proportion rows require unit = \"proportion\".", call. = FALSE)
  }
  if (!inherits(design, "nis_survey") || !is.list(design$design$cluster) ||
      length(design$design$cluster) < 1L) {
    stop("`design` must be an experimental survey design with a first-level cluster.",
         call. = FALSE)
  }
  fields <- names(design$design$variables)
  if (any(!specification$field %in% fields)) {
    stop("Every specification field must exactly match a retained design column.",
         call. = FALSE)
  }
  if (is.null(by)) {
    if (!is.null(group_missing)) stop("`group_missing` requires `by`.", call. = FALSE)
  } else {
    check_string(by, "by")
    if (!by %in% fields) stop("Grouping field must exactly match a retained design column.", call. = FALSE)
    group <- design$design$variables[[by]]
    if (!identical(class(group), "factor") || !is.null(dim(group))) {
      stop("`by` must name an exact retained standard unordered factor.", call. = FALSE)
    }
    extra_attributes <- setdiff(names(attributes(group)), c("levels", "class", "names"))
    if (length(extra_attributes)) {
      stop("`by` must be a standard factor without additional attributes.", call. = FALSE)
    }
    group_levels <- levels(group)
    if (!is.character(group_levels) || is.object(group_levels) ||
        !is.null(dim(group_levels)) || !is.null(attributes(group_levels)) || anyNA(group_levels) ||
        any(!nzchar(trimws(group_levels))) || anyDuplicated(group_levels)) {
      stop("Grouping factor levels must be unique, nonmissing, nonblank plain character labels.",
           call. = FALSE)
    }
    if (any(!is.na(group) & is.na(as.character(group)))) {
      stop("Grouping factor contains invalid level codes.", call. = FALSE)
    }
    if (base::missing(group_missing) || is.null(group_missing)) {
      stop("Choose explicit `group_missing = \"fail\"` or `\"exclude\"` when grouping.", call. = FALSE)
    }
    check_string(group_missing, "group_missing")
    if (!group_missing %in% c("fail", "exclude")) {
      stop("`group_missing` must be exactly \"fail\" or \"exclude\".", call. = FALSE)
    }
    unknown <- sum(is.na(group))
    if (group_missing == "fail" && unknown > 0L) {
      stop("Grouping field contains missing membership; choose exclusion or resolve it.", call. = FALSE)
    }
    observed <- group_levels[group_levels %in% as.character(group[!is.na(group)])]
    unused <- group_levels[!group_levels %in% observed]
    if (!length(observed)) stop("Grouping field has no observed groups.", call. = FALSE)
    grouped <- lapply(seq_along(observed), function(g) {
      level <- observed[[g]]
      predicate <- stats::as.formula(call("~", call("==", as.name(by), level)), env = baseenv())
      domain <- nis_domain(design, predicate, group_missing)
      part <- nis_descriptive_table(domain, specification, missing, df, confidence, variance)
      part$data$id <- paste0("g", g, ".", part$data$id)
      part$data$label <- paste0(part$data$label, " | ", by, " = ", level)
      names(part$results) <- part$data$id
      list(data = part$data, results = part$results)
    })
    data <- do.call(rbind, lapply(grouped, `[[`, "data"))
    rownames(data) <- NULL
    results <- unlist(lapply(grouped, `[[`, "results"), recursive = FALSE)
    declarations <- data[, c("id", "field", "statistic", "label", "unit"), drop = FALSE]
    provenance <- list(declarations = declarations,
      policies = list(missing = missing, df = df, confidence = confidence,
                      variance = variance, interval_scope = "pointwise"),
      constructor = design$provenance, population = design$population,
      domains = design$domains,
      grouping = list(field = by, observed_levels = observed, unused_levels = unused,
        unknown = as.double(unknown), missing = group_missing),
      scope = "experimental_numeric_descriptive_table", analysis_ready = FALSE)
    return(structure(list(data = data, results = results, provenance = provenance),
      class = "nis_descriptive_table"))
  }
  estimates <- lapply(seq_len(nrow(specification)), function(i) {
    nis_estimate(design, specification$field[[i]], specification$statistic[[i]],
      missing, df, confidence, variance)
  })
  results <- stats::setNames(estimates, specification$id)
  values <- data.frame(estimand = vapply(estimates, `[[`, character(1), "estimand"),
    weighted_estimate = vapply(estimates, `[[`, numeric(1), "estimate"),
    se = vapply(estimates, `[[`, numeric(1), "se"),
    lower = vapply(estimates, `[[`, numeric(1), "lower"),
    upper = vapply(estimates, `[[`, numeric(1), "upper"),
    df = vapply(estimates, `[[`, numeric(1), "df"),
    confidence = vapply(estimates, `[[`, numeric(1), "confidence"),
    raw_supplied = vapply(estimates, function(x) as.double(x$sample$supplied), numeric(1)),
    raw_included = vapply(estimates, function(x) as.double(x$sample$included), numeric(1)),
    raw_missing = vapply(estimates, function(x) as.double(x$sample$excluded_missing), numeric(1)),
    weighted_denominator = vapply(estimates, function(x) x$sample$weighted_denominator, numeric(1)),
    analysis_hospitals = vapply(estimates, function(x) {
      as.double(length(unique(x$design$cluster[[1L]])))
    }, numeric(1)),
    disclosure_status = rep("unreviewed", length(estimates)),
    stringsAsFactors = FALSE, check.names = FALSE)
  data <- specification
  for (name in names(values)) data[[name]] <- values[[name]]
  rownames(data) <- NULL
  provenance <- list(declarations = specification,
    policies = list(missing = missing, df = df, confidence = confidence,
                    variance = variance, interval_scope = "pointwise"),
    constructor = design$provenance, population = design$population,
    domains = design$domains,
    scope = "experimental_numeric_descriptive_table", analysis_ready = FALSE)
  structure(list(data = data, results = results, provenance = provenance),
            class = "nis_descriptive_table")
}
