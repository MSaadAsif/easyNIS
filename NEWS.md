# easyNIS 0.1.0.9000

- Replaced the archived API with lazy annual Parquet opening, ICD-10 prefix
  flags, a domain survey design, HCUP labels, CPI-adjusted charges and costs,
  cell suppression, and an invented six-year fixture.
- The placeholder-row survey method is experimental and must agree with the
  full-data design on estimates, standard errors and degrees of freedom.
- Added a short tidyverse pipeline README and retained the analyst workflow
  note that motivated the redesign.
- `nis_flag_dx()` and `nis_flag_pr()` now match each flag with one
  case-insensitive regex per slot, so lazy Arrow queries no longer error on
  malformed UTF-8 in code columns. Codes with characters other than letters,
  numbers, periods or whitespace never match.
- Added experimental `nis_comorbidity()`, which adds AHRQ Elixhauser Refined
  condition flags and mortality/readmission index scores to a collected data
  frame or an `nis_design()` result from `I10_DX1`, `I10_DX2`, ... by delegating
  to the suggested `medicalcoder` package. Present-on-admission is not used,
  `I10_DX1` is the principal diagnosis, and the output is not expected to
  match the Stata-derived `ynel*` and `elixsum` columns.
