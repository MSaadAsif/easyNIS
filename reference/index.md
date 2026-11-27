# Package index

## 

Open and inspect data

Open annual NIS files and inspect data structure and labels.

- [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
  : Write an invented NIS-shaped Parquet dataset
- [`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)
  : Save a reusable NIS cohort
- [`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md)
  : Convert a NIS file to annual Parquet
- [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
  : Open annual NIS Parquet files lazily
- [`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md)
  : Attach an annual NIS companion to Core discharges
- [`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
  : Apply HCUP labels
- [`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_demographics()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_hospital()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  : Select NIS column groups

## 

Define cohorts

Flag codes, timing, and eligibility; audit cohort definitions.

- [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
  : Add diagnosis code flags
- [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
  : Add procedure code flags
- [`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)
  : Flag procedure timing relative to an index procedure
- [`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md)
  : Summarize procedure-day completeness by year and procedure slot
- [`nis_add_ccsr()`](https://msaadasif.github.io/easyNIS/reference/nis_add_ccsr.md)
  : Add CCSR categories to a NIS query
- [`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md)
  : ICD-10 codes in HCUP CCSR categories
- [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  [`nis_attrition_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  : Summarize sequential cohort attrition
- [`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md)
  : Summarize diagnosis-position sensitivity
- [`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md)
  : Audit code-group frequencies across periods

## 

Design and estimate

Build survey designs and apply optional reweighting.

- [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  : Prepare a cohort survey design
- [`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md)
  : Report the design and fitted sample for NIS analyses
- [`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
  : Create a lazy whole-sample NIS survey design
- [`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
  : Reweight a cohort survey design
- [`nis_annual_totals()`](https://msaadasif.github.io/easyNIS/reference/nis_annual_totals.md)
  : Estimate annual national discharge totals

## 

Add analysis variables

Derive discharge outcomes, comorbidity indicators, and
inflation-adjusted costs.

- [`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)
  : Add standard discharge outcomes
- [`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
  : Add comorbidity indicators and scores (experimental)
- [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  : Adjust NIS charges and costs to a reference dollar year
- [`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md)
  : Read cost adjustment provenance

## 

Review outputs

Count supporting hospitals and suppress disclosure-prone cells.

- [`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
  : Count discharges and contributing hospitals by cell
- [`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
  : Suppress small unweighted cells in a survey summary

## 

Create a study skeleton

Create a Quarto project with a starter analysis file. Add your data and
study-specific definitions and analysis.

- [`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md)
  : Create a new NIS study folder
