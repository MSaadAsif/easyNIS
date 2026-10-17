# easyNIS 0.1.0.9000

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
- `nis_flag_dx()` and `nis_flag_pr()` now match each flag with one
  case-insensitive regex per slot, so lazy Arrow queries no longer error on
  malformed UTF-8 in code columns. Codes with characters other than letters,
  numbers, periods or whitespace never match.
