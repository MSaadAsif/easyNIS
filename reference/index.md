# Package index

## Convert, open, and join

Prepare annual files, open them in DuckDB, and select or label analysis
fields.

- [`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md)
  : Convert a NIS file to annual Parquet
- [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
  : Open annual NIS Parquet files lazily
- [`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md)
  : Join an annual NIS companion file
- [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
  : Create invented NIS Parquet files
- [`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
  : Apply HCUP labels
- [`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_demographics()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  [`nis_vars_hospital()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
  : Select NIS column groups

## Define and save cohorts

Match clinical codes, count eligibility steps, and save a reusable
cohort.

- [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
  : Add diagnosis code flags
- [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
  : Add procedure code flags
- [`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)
  : Flag procedure timing relative to an index procedure
- [`nis_add_ccsr()`](https://msaadasif.github.io/easyNIS/reference/nis_add_ccsr.md)
  : Add CCSR categories to a NIS query
- [`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md)
  : Find ICD-10 codes in a CCSR category
- [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  [`nis_attrition_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  : Count discharges at each eligibility step
- [`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)
  : Save a reusable NIS cohort

## Audit coding and completeness

Compare code frequencies, diagnosis positions, and procedure-day
coverage.

- [`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md)
  : Audit code-group frequencies across periods
- [`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md)
  : Compare principal and any-slot diagnosis matches
- [`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md)
  : Check procedure-day completeness

## Derive outcomes, comorbidities, and costs

Add discharge outcomes, score comorbidities, and express costs in a
common dollar year.

- [`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)
  : Add standard discharge outcomes
- [`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
  : Add comorbidity indicators and scores (experimental)
- [`nis_comorbidity_condition_map()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity_condition_map.md)
  : Map comorbidity output flags to distinct conditions
- [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  : Adjust NIS charges and costs to a reference dollar year
- [`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md)
  : Read cost adjustment provenance

## Estimate with the survey design

Build cohort or whole-sample designs, estimate annual totals, and report
the fitted sample.

- [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  : Prepare a cohort survey design
- [`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
  : Create a lazy whole-sample NIS survey design
- [`nis_annual_totals()`](https://msaadasif.github.io/easyNIS/reference/nis_annual_totals.md)
  : Estimate annual national discharge totals
- [`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
  : Reweight a cohort survey design
- [`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md)
  : Report the survey design and fitted sample

## Check disclosure

Count supporting discharges and hospitals, mask small cells, and scan
publication files.

- [`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
  : Count discharges and contributing hospitals by cell
- [`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
  : Mask cells with insufficient disclosure support
- [`nis_scan_outputs()`](https://msaadasif.github.io/easyNIS/reference/nis_scan_outputs.md)
  : Scan a publication folder for disclosure risks

## Start a reproducible study

Create a Quarto project with a sample analysis and a disclosure
checklist.

- [`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md)
  : Create a Quarto study
