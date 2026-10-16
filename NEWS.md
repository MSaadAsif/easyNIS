# easyNIS 0.1.0.9000

- Added experimental `nis_reweight()` for multiplying cohort survey weights
  while retaining placeholder rows, with an optional commented WeightIt and
  cobalt example in the study template.
- Replaced the archived API with lazy annual Parquet opening, ICD-10 prefix
  flags, a domain survey design, HCUP labels, CPI-adjusted charges and costs,
  cell suppression, and an invented six-year fixture.
- The placeholder-row survey method is experimental and must agree with the
  full-data design on estimates, standard errors and degrees of freedom.
- Added a short tidyverse pipeline README and retained the analyst workflow
  note that motivated the redesign.
