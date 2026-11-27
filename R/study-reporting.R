nis_study_coding_eras <- function(years, quarters) {
  transition <- years == 2015L
  unknown <- any(transition) && (!length(quarters) || !all(quarters[transition] %in% as.character(1:4)))
  eras <- c(
    if (any(years < 2015L) || any(transition & quarters %in% as.character(1:3))) "ICD-9-CM",
    if (any(years > 2015L) || any(transition & quarters %in% "4")) "ICD-10-CM/PCS"
  )
  list(text = paste(eras, collapse = " and "), unknown = unknown, review = unknown || length(eras) > 1L)
}

nis_study_design_status <- function(design, input) {
  records <- design$variables
  strata <- paste(records$YEAR, records$NIS_STRATUM, sep = "::")
  clusters <- paste(strata, paste(records$YEAR, records$HOSP_NIS, sep = "::"), sep = ".")
  weights <- stats::weights(design)
  list(
    weighted = length(weights) > 0L &&
      !isTRUE(input$reweighted) &&
      isTRUE(all.equal(as.numeric(weights), as.numeric(records$DISCWT) / input$divisor)),
    taylor = inherits(design, "survey.design2") &&
      is.null(design$fpc$popsize) &&
      identical(as.character(design$strata[[1L]]), strata) &&
      identical(as.character(design$cluster[[1L]]), clusters)
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_trend_estimates <- function(design) {
  trend <- design |>
    dplyr::mutate(.one = 1) |>
    dplyr::group_by(YEAR) |>
    dplyr::summarise(
      mortality = srvyr::survey_mean(.data$DIED, vartype = "ci", na.rm = TRUE),
      mean_los = srvyr::survey_mean(.data$LOS, vartype = "ci", na.rm = TRUE),
      weighted_n = srvyr::survey_total(.data$.one, vartype = NULL),
      .groups = "drop"
    ) |>
    dplyr::ungroup()
  attr(trend, "nis_trend_source") <- list(design = design, values = rlang::hash(trend))
  trend
}

nis_study_trend_verified <- function(trend, design) {
  source <- attr(trend, "nis_trend_source", exact = TRUE)
  attr(trend, "nis_trend_source") <- NULL
  identical(source$design, design) && identical(source$values, rlang::hash(trend))
}

nis_study_estimates_verified <- function(tables, models, trend, design) {
  tables <- Filter(Negate(is.null), tables)
  checks <- c(
    vapply(
      tables,
      function(table) {
        inherits(table, "tbl_svysummary") && identical(table$inputs$data, design)
      },
      logical(1)
    ),
    vapply(
      models,
      function(model) {
        inherits(model, "svyglm") && identical(model$survey.design, design)
      },
      logical(1)
    ),
    if (!is.null(trend)) nis_study_trend_verified(trend, design)
  )
  length(checks) > 0L && all(checks)
}

nis_study_release_status <- function(code) {
  switch(
    if (is.null(code)) "unknown" else code,
    matched = c("Pass", "Opened years matched HCUP's published annual release totals."),
    `non-release` = c("Not applicable", "The opened files were marked as non-release data."),
    mismatch = c(
      "Needs attention",
      "The annual release check found discrepancies. Review the input for a partial extract."
    ),
    failed = c("Needs attention", "The annual release check could not run."),
    c("Needs attention", "Release totals were skipped or could not be verified for all opened years.")
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_checklist <- function(report, tables, models, trend, design) {
  pass <- function(ok) if (isTRUE(ok)) "Pass" else "Needs attention"
  review <- "Analyst review"
  na <- "Not applicable"
  verified <- nis_study_estimates_verified(tables, models, trend, design)
  weighted <- report$design$weighted && verified
  release <- nis_study_release_status(report$release)
  design_ok <- report$design$taylor && report$domain && verified && release[[1L]] != "Needs attention"
  dplyr::tribble(
    ~Practice, ~Status, ~Evidence,
    "DUA and training", review, "Verify DUA, training, and authorized use.",
    "Small-cell and hospital suppression", review,
    "Check the built-in masks and review any added results for protected cells.",
    "Indirect disclosure across outputs", review, "Check overlapping releases and external totals for derivable cells.",
    "Cite HCUP, NIS, and HCUP tools", review,
    "Methods cites HCUP and NIS. Check the abstract and citations in the final manuscript.",
    "Acknowledge HCUP partners", review, "Check the acknowledgements for the contributing partners.",
    "Annual release integrity", release[[1L]], release[[2L]],
    "Sampling design", pass(design_ok),
    "Compared the reported estimates with the clustered, stratified design and checked the opened sample size.",
    "Inpatient stays as the unit of analysis", review, "Check the manuscript's unit of analysis and interpretation.",
    "Facility exclusions", review, "Check rehabilitation and long-term acute care exclusions.",
    "State-level inference", review, "Check geographic claims and targets.",
    "Facility-level totals and hospital volume", review, "Check facility-level estimates and their interpretation.",
    "Physician-level inference", review, "Check for physician-level claims.",
    "Patient follow-up", review, "Check for patient linkage and longitudinal claims.",
    "ICD definitions appropriate for outcomes", review, "Check clinical validity and code definitions.",
    "Distinguish comorbidities from complications", review, "Check whether diagnoses represent in-hospital complications.",
    "Annual data-element availability", review, "Compare field definitions and code-slot coverage across years.",
    "National weights", pass(weighted),
    "Compared the survey weights with DISCWT and checked the source of the reported estimates.",
    "Standard errors and hospital nesting", pass(design_ok),
    "Checked the survey design attached to the reported estimates for strata and clusters.",
    "Survey domain", pass(report$domain),
    if (report$domain) "The design input and opened sample had the same row count."
    else "The design input row count differs or is unavailable. Check for a pre-design filter.",
    "Missing data", review, "Check exclusions and missingness in the analysis variables and models.",
    "Population denominators", review, "Check whether population denominators are needed for the estimands.",
    "Incidence and prevalence", review, "Check whether these interpretations are supported.",
    "Sampling redesign and historical trend weights", if (all(report$years >= 2012L)) na else review,
    "Inspect any trends crossing a historical NIS redesign.",
    "ICD coding transition", if (report$coding$review) review else na, report$coding$text,
    "Trends across the 2015 transition", if (report$coding$review) review else na,
    "Check clinical equivalence and how the discontinuity was handled.",
    "Current HCUP coding tools", review, "Check the selection and currency of any HCUP coding tools.",
    "Annualization of partial years", if (!isTRUE(report$annualize)) na else pass(report$full_years),
    "Checked valid-design years against the requested years and quarter coverage among cohort discharges."
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_reporting <- function(opened, design, requested_years) {
  input <- nis_design_report(design)
  opened_n <- opened |> dplyr::summarise(rows = dplyr::n()) |> nis_collect()
  requested_years <- as.integer(unlist(requested_years, use.names = FALSE))
  records <- design$variables
  quarter <- sub("^Q", "", as.character(records$DQTR))
  quarters <- if (length(quarter)) split(quarter, records$YEAR)
  list(
    years = input$years,
    coding = nis_study_coding_eras(records$YEAR, quarter),
    cohort = input$cohort,
    domain = identical(input$input_n, as.numeric(opened_n$rows)),
    annualize = input$annualize,
    divisor = input$divisor,
    reweighted = input$reweighted,
    full_years = setequal(input$years, requested_years) &&
      setequal(names(quarters), as.character(requested_years)) &&
      all(vapply(quarters, setequal, logical(1), y = as.character(1:4))),
    release = opened$src$.easyNIS_release_check,
    design = nis_study_design_status(design, input),
    cost = nis_cost_provenance(design),
    lonely = getOption("survey.lonely.psu", "fail"),
    domain_lonely = isTRUE(getOption("survey.adjust.domain.lonely"))
  )
}

# jarl-ignore unused_function: Called by the bundled Quarto study.
nis_study_methods <- function(report, is_example) {
  package_names <- c("easyNIS", "duckdb", "dplyr", "srvyr", "survey", "gtsummary")
  versions <- vapply(package_names, function(name) as.character(utils::packageVersion(name)), character(1))
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
    if (nzchar(report$coding$text)) paste0("The analytic cohort included ", report$coding$text, " coding."),
    if (report$coding$unknown) {
      "The ICD coding era could not be determined for 2015 records with missing or invalid discharge quarters."
    },
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
    "Discharges with missing, nonfinite, or nonpositive YEAR, HOSP_NIS, NIS_STRATUM, or DISCWT were excluded before defining the domain.",
    "Summary table headers show cohort or group N. Estimate denominators and model sample sizes are unweighted.",
    nis_study_methods_survey(report),
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

nis_study_methods_survey <- function(report) {
  paste(
    if (report$design$weighted || isTRUE(report$reweighted)) {
      adjustment <- if (isTRUE(report$annualize)) {
        units <- ngettext(report$divisor, "year", "years")
        paste(" divided by", report$divisor, "valid-design", units, "(annualization).")
      } else {
        "."
      }
      paste0("The survey design used base weights from DISCWT", adjustment)
    },
    if (isTRUE(report$reweighted)) "The base discharge weights were multiplied by supplied reweighting factors.",
    if (report$design$taylor) {
      paste(
        "The design uses a with-replacement Taylor linearization approximation without a finite population correction, with year-specific HOSP_NIS clusters",
        "nested in year-specific NIS_STRATUM strata, following",
        "[HCUP variance guidance](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp).",
        sprintf(
          "Singleton PSU handling was `%s` (domain adjustment %s).",
          report$lonely,
          if (report$domain_lonely) "enabled" else "disabled"
        )
      )
    }
  )
}
