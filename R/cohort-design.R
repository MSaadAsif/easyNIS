.nis_cohort_structure_fields <- c(".nis_psu", ".nis_stratum", ".nis_weight", ".in_cohort")

# Cohort rows plus placeholder rows (`.in_cohort == FALSE`) in one nested
# design, filtered to the cohort. The placeholders and the cohort row count
# stay on the result so `nis_reweight()` can rebuild the design.
nis_cohort_design <- function(combined, excluded, cost_provenance) {
  design <- srvyr::as_survey_design(
    combined,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = TRUE
  ) |>
    dplyr::filter(.in_cohort)
  attr(design, "nis_placeholder_rows") <- combined[!combined$.in_cohort, , drop = FALSE]
  attr(design, "nis_cohort_rows") <- sum(combined$.in_cohort)
  attr(design, "nis_excluded") <- excluded
  attr(design, "nis_cost_provenance") <- cost_provenance
  design
}

nis_cohort_records <- function(data) {
  if (".in_cohort" %in% names(data)) dplyr::filter(data, .in_cohort) else data
}

nis_cohort_design_rows <- function(design, call) {
  placeholders <- attr(design, "nis_placeholder_rows", exact = TRUE)
  cohort_rows <- attr(design, "nis_cohort_rows", exact = TRUE)
  if (any(c(!inherits(design, "tbl_svy"), !is.data.frame(placeholders), is.null(cohort_rows)))) {
    cli::cli_abort("`design` must be a result of `nis_design()`.", call = call)
  }
  variables <- design$variables
  if (nrow(variables) != cohort_rows) {
    cli::cli_abort(
      c(
        "`design` has been narrowed with `filter()`.",
        i = "Call `nis_reweight()` before narrowing the cohort."
      ),
      call = call
    )
  }

  list(variables = variables, placeholders = placeholders)
}

nis_cohort_design_restore <- function(design, call) {
  if (
    any(c(
      ncol(design$cluster) != 1L,
      ncol(design$strata) != 1L,
      !is.null(design$postStrata),
      !is.null(design$fpc$popsize),
      !identical(design$pps, FALSE)
    ))
  ) {
    cli::cli_abort("`design` has unsupported survey structure for reweighting.", call = call)
  }
  stratum <- as.character(design$strata[[1L]])
  psu <- as.character(design$cluster[[1L]])
  prefix <- paste0(stratum, ".")
  if (!all(startsWith(psu, prefix))) {
    cli::cli_abort("`design` has unsupported PSU identities for reweighting.", call = call)
  }
  variables <- design$variables
  variables$.nis_psu <- substring(psu, nchar(prefix) + 1L)
  variables$.nis_stratum <- stratum
  variables$.nis_weight <- as.numeric(stats::weights(design))
  variables$.in_cohort <- rep(TRUE, nrow(variables))
  variables
}

nis_cohort_check_rebuild <- function(original, rebuilt, call) {
  same_ids <- function(field) {
    identical(as.character(original[[field]][[1L]]), as.character(rebuilt[[field]][[1L]]))
  }
  if (!same_ids("cluster") || !same_ids("strata") || !identical(original$fpc, rebuilt$fpc)) {
    cli::cli_abort("`design` variance structure cannot be safely rebuilt for reweighting.", call = call)
  }
}
