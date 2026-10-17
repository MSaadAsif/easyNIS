# easyNIS 0.2.0.9000

## Documentation

- Added runnable examples for every exported helper using invented fixtures;
  the slower optional comorbidity example is marked `donttest`.
- Added a Getting started guide covering opening files, flags, survey design,
  weighted tables, models, primary-cell suppression, and study scaffolding.
- Grouped the local pkgdown reference by workflow; no site is deployed.

## Core workflow

- Added experimental 2012–2015 opening, explicit `system = "icd9"` prefix
  flags, metadata guards, and invented historical/split-2015 fixtures.
  ICD-10 remains the default; cross-era clinical definitions are analyst supplied.

- Experimental NIS 2023 layout support, UNVERIFIED against official HCUP 2023
  documentation and real 2023 data (the `TOTCHG_2023` field, removed
  `HOSP_REGION` and `HOSP_DIVISION`, and sequential `NIS_STRATUM` are assumed
  from secondary notes; none was tested on real data). `nis_open()` accepts
  files without `HOSP_REGION` and `HOSP_DIVISION`, keeps `TOTCHG_2023` as its
  own column, never changes `TOTCHG`, and warns once per session when a query
  contains `TOTCHG_2023`, because HCUP's national-estimate adjustment makes it
  not comparable with earlier-year charges. `nis_design()` and `nis_cost()`
  gain a `charges` argument (default `"TOTCHG"`); pass `"TOTCHG_2023"` or
  pool explicitly with `mutate()` to opt in. `PL_NCHS2` is labelled; geography
  columns remain optional. Hospital and stratum IDs stay qualified by year.
- Replaced the archived API with lazy annual Parquet opening, ICD-10 prefix
  flags, a domain survey design, HCUP labels, CPI-adjusted charges and costs,
  cell suppression, and an invented six-year fixture.
- The placeholder-row survey method is experimental and must agree with the
  full-data design on estimates, standard errors and degrees of freedom.
- Added a short tidyverse pipeline README and retained the analyst workflow
  note that motivated the redesign.
- `nis_flag_dx()` and `nis_flag_pr()` match literal prefixes separately in
  each slot. Supplied prefixes ignore case, periods, and spaces; stored NIS
  codes are compared byte for byte without text normalization, so malformed
  UTF-8 cannot raise a matching error.

## Experimental helpers
- Added experimental `nis_reweight()` for multiplying cohort survey weights
  while retaining placeholder rows, with an optional commented WeightIt and
  cobalt example in the study template.
- Added experimental `nis_comorbidity()`, which adds AHRQ Elixhauser Refined
  condition flags and mortality/readmission index scores to a collected data
  frame or an `nis_design()` result from `I10_DX1`, `I10_DX2`, ... by delegating
  to the suggested `medicalcoder` package. Present-on-admission is not used,
  `I10_DX1` is the principal diagnosis, and the output is not expected to
  match the Stata-derived `ynel*` and `elixsum` columns.
- Added experimental `nis_ccsr_codes()`, which reads an HCUP DXCCSR or PRCCSR
  reference file you download (Excel with readxl, or comma-separated) and
  returns the ICD-10 codes in chosen CCSR categories, optionally only where the
  category is the default inpatient assignment. Pass the codes to
  `nis_flag_dx()` or `nis_flag_pr()`. No CCSR content is bundled.
- Added a vignette on porting existing NIS study code, and CI workflows for
  linting, test coverage and rendering the study template.
