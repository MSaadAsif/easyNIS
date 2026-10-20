# Package index

## 

Open and inspect data

Open annual NIS files and inspect data structure and labels.

- [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
  : Write an invented NIS-shaped Parquet dataset
- [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
  : Open annual NIS Parquet files lazily
- [`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
  : Apply HCUP labels

## 

Define cohorts

Flag codes, timing, and eligibility; audit cohort definitions.

- [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
  : Add diagnosis prefix flags
- [`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md)
  : Add diagnosis position flags
- [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
  : Add procedure prefix flags
- [`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)
  : Flag procedure timing relative to an index procedure
- [`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)
  : Summarize procedure-day completeness by year and procedure slot
- [`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md)
  : ICD-10 codes in HCUP CCSR categories
- [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  : Summarize sequential cohort attrition
- [`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md)
  : Summarize diagnosis-position sensitivity
- [`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md)
  : Audit code-group frequencies across periods

## 

Design and estimate

Build survey designs and apply optional reweighting.

- [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  : Prepare a cohort survey design
- [`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
  : Reweight a cohort survey design

## 

Add analysis variables

Compute comorbidity indicators and inflation-adjusted costs.

- [`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
  : Add AHRQ Elixhauser comorbidity columns (experimental)
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

Start a Quarto study folder (template workflow deferred).

- [`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md)
  : Create a new NIS study folder
