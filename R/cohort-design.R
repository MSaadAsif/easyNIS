.nis_cohort_structure_fields <- c(".nis_psu", ".nis_stratum", ".nis_weight")

# Build the survey structure over the cohort and placeholders before attaching
# the analysis data, so restricting the domain never slices those columns.
nis_cohort_design <- function(variables, structure, placeholders, excluded,
                              cost_provenance, nest = TRUE) {
  design <- srvyr::as_survey_design(
    structure,
    ids = .nis_psu,
    strata = .nis_stratum,
    weights = .nis_weight,
    nest = nest,
    check_strata = FALSE
  )
  design$variables <- NULL
  if (nrow(placeholders) > 0L) {
    design <- design[seq_len(nrow(variables)), ]
  }
  # Use survey's subset representation for with-replacement designs.
  design$fpc$popsize <- NULL
  design$variables <- dplyr::as_tibble(variables)
  attr(design, "survey_vars") <- NULL
  attr(design, "nis_placeholder_rows") <- placeholders
  attr(design, "nis_cohort_rows") <- nrow(variables)
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
  if (any(c(!inherits(design, "tbl_svy"), !is.data.frame(placeholders),
      is.null(cohort_rows)))) {
    cli::cli_abort("`design` must be a result of `nis_design()`.", call = call)
  }
  variables <- design$variables
  if (nrow(variables) != cohort_rows) {
    cli::cli_abort(c(
      "`design` has been narrowed with `filter()`.",
      i = "Call `nis_reweight()` before narrowing the cohort."
    ), call = call)
  }

  list(variables = variables, placeholders = placeholders)
}

nis_cohort_design_restore <- function(design, call) {
  if (any(c(ncol(design$cluster) != 1L, ncol(design$strata) != 1L,
      !is.null(design$postStrata), !is.null(design$fpc$popsize),
      !identical(design$pps, FALSE)))) {
    cli::cli_abort("`design` has unsupported survey structure for reweighting.", call = call)
  }
  stratum <- as.character(design$strata[[1L]])
  psu <- as.character(design$cluster[[1L]])
  prefix <- paste0(stratum, ".")
  if (!all(startsWith(psu, prefix))) {
    cli::cli_abort("`design` has unsupported PSU identities for reweighting.", call = call)
  }
  dplyr::tibble(
    .nis_psu = substring(psu, nchar(prefix) + 1L),
    .nis_stratum = stratum,
    .nis_weight = as.numeric(stats::weights(design))
  )
}

nis_cohort_check_rebuild <- function(original, rebuilt, call) {
  same_ids <- function(field) {
    identical(as.character(original[[field]][[1L]]),
      as.character(rebuilt[[field]][[1L]]))
  }
  if (!same_ids("cluster") || !same_ids("strata") ||
      !identical(original$fpc, rebuilt$fpc)) {
    cli::cli_abort("`design` variance structure cannot be safely rebuilt for reweighting.", call = call)
  }
}
