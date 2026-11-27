nis_study_preserves_sample <- function(source, query, fields) {
  if (identical(query, source)) {
    return(TRUE)
  }
  # Only row-preserving projections may intervene between open and design.
  # Treat unknown dbplyr operations conservatively.
  if (
    any(c(
      !inherits(query, "lazy_select_query"),
      !query$select_operation %in% c("select", "mutate"),
      !is.null(query$where),
      !is.null(query$limit),
      isTRUE(query$distinct)
    ))
  ) {
    return(FALSE)
  }
  selected <- query$select
  indices <- match(fields, selected$name)
  unchanged <- identical(selected$expr[indices], rlang::syms(fields))
  unchanged && nis_study_preserves_sample(source, query$x, fields)
}

nis_study_design <- function(opened, .data, cohort, keep, annualize = FALSE, dollars = NULL) {
  cohort <- rlang::enquo(cohort)
  keep <- rlang::enquo(keep)
  fields <- c(.nis_design_fields, intersect("DQTR", names(opened)))
  full_sample <- identical(dbplyr::remote_con(opened), dbplyr::remote_con(.data)) &&
    nis_study_preserves_sample(opened$lazy_query, .data$lazy_query, fields)
  design <- nis_design(.data, !!cohort, !!keep, annualize = annualize, dollars = dollars)
  attr(design, "nis_study_design") <- list(
    cohort = rlang::expr_text(rlang::quo_get_expr(cohort)),
    full_sample = full_sample,
    annualize = annualize
  )
  design
}

nis_study_coverage <- function(opened) {
  opened |>
    nis_sample_fields(rlang::quo(TRUE)) |>
    dplyr::select(YEAR, dplyr::any_of("DQTR"), dplyr::all_of(".nis_valid")) |>
    dplyr::distinct() |>
    nis_collect()
}

nis_study_coding_eras <- function(coverage) {
  years <- coverage$YEAR
  quarters <- as.character(coverage$DQTR)
  transition <- years == 2015L
  unknown <- any(transition) && (!length(quarters) || !all(quarters[transition] %in% as.character(1:4)))
  eras <- c(
    if (any(years < 2015L) || any(transition & quarters %in% as.character(1:3))) "ICD-9-CM",
    if (any(years > 2015L) || any(transition & quarters %in% "4")) "ICD-10-CM/PCS",
    if (unknown) "2015 with unverified quarter coverage"
  )
  list(text = paste(eras, collapse = " and "), review = unknown || length(eras) > 1L)
}

nis_study_design_status <- function(design, annualize) {
  records <- design$variables
  placeholders <- attr(design, "nis_placeholder_rows", exact = TRUE)
  strata <- paste(records$YEAR, records$NIS_STRATUM, sep = "::")
  clusters <- paste(strata, paste(records$YEAR, records$HOSP_NIS, sep = "::"), sep = ".")
  years <- union(records$YEAR, as.integer(sub("::.*", "", placeholders$.nis_stratum)))
  divisor <- if (isTRUE(annualize)) length(years) else 1L
  weights <- stats::weights(design)
  list(
    divisor = divisor,
    weighted = length(weights) > 0L &&
      isTRUE(all.equal(as.numeric(weights), as.numeric(records$DISCWT) / divisor)),
    taylor = inherits(design, "survey.design2") &&
      is.null(design$fpc$popsize) &&
      identical(as.character(design$strata[[1L]]), strata) &&
      identical(as.character(design$cluster[[1L]]), clusters)
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_checklist <- function(report, tables, models, is_example) {
  pass <- function(ok) if (isTRUE(ok)) "Pass" else "Needs attention"
  review <- "Needs attention"
  na <- "Not applicable"
  weighted <- report$design$weighted && any(tables != "cohort flow")
  design_ok <- report$design$taylor && report$domain && weighted
  displayed <- toString(tables)
  fits <- toString(models)
  dplyr::tribble(
    ~Practice, ~Status, ~Evidence,
    "DUA and training", ifelse(is_example, na, review),
    ifelse(is_example, "The scaffold generated invented discharges.", "Verify DUA, training, and authorized use."),
    "Small-cell and hospital suppression", ifelse(length(tables) > 0L, "Pass", na),
    paste0("Built-in disclosure policy applied to ", displayed, "."),
    "Indirect disclosure across outputs", review,
    "Check overlapping releases and external totals for derivable cells.",
    "Cite HCUP, NIS, and HCUP tools", review,
    "Methods cites HCUP and NIS. Check the abstract and citations in the final manuscript.",
    "Acknowledge HCUP partners", ifelse(is_example, na, review),
    "Check the acknowledgements for the contributing partners.",
    "Sampling design", pass(design_ok),
    "Checked the weights, year-specific strata and clusters, and preservation of the opened sample.",
    "Inpatient stays as the unit of analysis", "Pass",
    "The generated Methods describes inpatient discharges.",
    "Facility exclusions", ifelse(is_example, na, review),
    "Confirm the intended population accounts for rehabilitation and long-term acute care exclusions.",
    "State-level inference", na, "The built-in estimates have no state-level targets.",
    "Facility-level totals and hospital volume", na, "Hospitals enter the design and disclosure calculations.",
    "Physician-level inference", na, "The built-in estimates have no physician-level targets.",
    "Patient follow-up", na, "The scaffold performs no patient linkage.",
    "ICD definitions appropriate for outcomes", review, "Clinical meaning and validity require analyst review.",
    "Distinguish comorbidities from complications", review,
    "Methods and model terms cannot establish whether a diagnosis represents an in-hospital complication.",
    "Annual data-element availability", ifelse(length(report$years) == 1L, na, review),
    "Compare field definitions and code-slot coverage across the opened years.",
    "National weights", pass(weighted),
    "Checked the survey weights against DISCWT and the observed valid-design year divisor.",
    "Standard errors and hospital nesting", pass(design_ok),
    paste("Checked the clustered, stratified survey design.", if (nzchar(fits)) paste("Reported survey models:", fits)),
    "Survey domain", pass(report$domain),
    if (report$domain) "The design input preserved the opened sample before domain restriction."
    else "The design input could not be matched to the opened sample. Check for a pre-design filter.",
    "Missing data", review, "Check design-field exclusions and missingness in the analysis variables and models.",
    "Population denominators", na, "The built-in estimates use discharge denominators.",
    "Incidence and prevalence", na, "The scaffold reports discharge summaries and associations.",
    "Sampling redesign and historical trend weights", if (all(report$years >= 2012L)) na else review,
    "Inspect trends crossing a historical NIS redesign.",
    "ICD coding transition", if (report$coding$review) review else na, report$coding$text,
    "Trends across the 2015 transition", if (report$coding$review) review else na,
    "Check clinical equivalence and how the discontinuity was handled.",
    "Current HCUP coding tools", na, "The built-in cohort uses code-prefix flags.",
    "Annualization of partial years", if (!isTRUE(report$annualize)) na else pass(report$full_years),
    "Annualization counts each valid-design year once. Check whether the analytic domain covers partial years."
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_reporting <- function(opened, design) {
  coverage <- nis_study_coverage(opened)
  coverage <- coverage[is.finite(coverage$YEAR) & coverage$YEAR > 0L, ]
  design_info <- attr(design, "nis_study_design", exact = TRUE)
  valid <- coverage[coverage$.nis_valid, ]
  list(
    years = sort(unique(coverage$YEAR)),
    coding = nis_study_coding_eras(coverage),
    cohort = design_info$cohort,
    domain = isTRUE(design_info$full_sample),
    annualize = design_info$annualize,
    full_years = isTRUE(design_info$full_sample) &&
      "DQTR" %in% names(valid) &&
      all(vapply(
        split(valid$DQTR, valid$YEAR),
        function(quarter) {
          setequal(as.character(quarter), as.character(1:4))
        },
        logical(1)
      )),
    design = nis_study_design_status(design, design_info$annualize),
    cost = nis_cost_provenance(design),
    lonely = getOption("survey.lonely.psu", "fail"),
    domain_lonely = isTRUE(getOption("survey.adjust.domain.lonely"))
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_methods <- function(report, is_example) {
  package_names <- c("easyNIS", "duckdb", "dplyr", "srvyr", "survey", "gtsummary")
  versions <- nis_study_package_versions(package_names)
  package_names[package_names == "duckdb"] <- "DuckDB"
  paste(
    if (is_example) {
      "This demonstration used invented inpatient discharges for NIS data years"
    } else {
      "This study used inpatient discharges from the [HCUP National Inpatient Sample](https://hcup-us.ahrq.gov/nisoverview.jsp) for data years"
    },
    paste0(paste(report$years, collapse = ", "), "."),
    if (is_example) {
      "The data layout follows the [HCUP National Inpatient Sample](https://hcup-us.ahrq.gov/nisoverview.jsp)."
    },
    paste0("The opened sample covered ", report$coding$text, " coding."),
    if (length(report$cohort)) paste0("The cohort criterion was `", report$cohort, "`."),
    if (report$domain) {
      paste(
        "The criterion was applied as a survey domain. The design retained",
        "zero-domain placeholders for hospital-years with no eligible discharges."
      )
    } else {
      paste(
        "The report could not verify that the design input retained the opened sample.",
        "Any domain variance applies to the sample supplied to the design."
      )
    },
    "Discharges with invalid design fields were excluded before defining the domain.",
    if (report$design$weighted) {
      adjustment <- if (isTRUE(report$annualize)) {
        paste(" divided by", report$design$divisor, "valid-design years (annualization).")
      } else {
        "."
      }
      paste0("Survey estimates used DISCWT", adjustment)
    },
    if (report$design$taylor) {
      paste(
        "Variance was estimated by Taylor linearization with year-specific HOSP_NIS clusters",
        "nested in year-specific NIS_STRATUM strata, following",
        "[HCUP variance guidance](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp).",
        sprintf(
          "Singleton PSU handling was `%s` (domain adjustment %s).",
          report$lonely,
          if (report$domain_lonely) "enabled" else "disabled"
        )
      )
    },
    if (!is.null(report$cost)) {
      sprintf(
        "Costs were estimated from %s and %s and expressed in %d US dollars using CPI-U.",
        report$cost$charge_field,
        report$cost$ccr_field,
        report$cost$base_year
      )
    },
    paste0("The analysis used R ", getRversion(), ", ", paste(package_names, versions, collapse = ", "), ".")
  )
}
