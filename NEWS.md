# easyNIS 0.1.0.9000

- Experimental NIS 2023 layout support: `nis_open()` accepts files without
  `HOSP_REGION` and `HOSP_DIVISION`, retains `TOTCHG_2023` and exposes it as
  the harmonized `TOTCHG` alias, and `nis_design()` accepts the 2023 charge
  field with `CCR_NIS`. `PL_NCHS2` is labelled; geography columns remain
  optional. Hospital and stratum IDs stay qualified by year. HCUP's 2023
  charge adjustment and removed `RACE` field mean some cross-year comparisons
  need care.
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
