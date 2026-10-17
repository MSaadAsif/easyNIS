# easyNIS 0.1.0.9000

- Replaced the archived API with lazy annual Parquet opening, ICD-10 prefix
  flags, a domain survey design, HCUP labels, CPI-adjusted charges and costs,
  cell suppression, and an invented six-year fixture.
- The placeholder-row survey method is experimental and must agree with the
  full-data design on estimates, standard errors and degrees of freedom.
- Added a short tidyverse pipeline README and retained the analyst workflow
  note that motivated the redesign.
- `nis_suppress()` now also masks the overall (`add_overall()`) cell in any row
  where a by-group cell is masked, so the masked count cannot be recovered by
  subtraction. Other derivable cells, such as those from column totals across
  levels, are still not masked; its footnote and the study template say to
  review tables before sharing.
- `nis_flag_dx()` and `nis_flag_pr()` now match each flag with one
  case-insensitive regex per slot, so lazy Arrow queries no longer error on
  malformed UTF-8 in code columns. Codes with characters other than letters,
  numbers, periods or whitespace never match.
