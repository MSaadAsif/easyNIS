# easyNIS (development version)

## New features

- Refactored internal CCSR mapping helpers to keep cyclomatic complexity within
  the repository limit without changing `nis_ccsr_codes()` behavior.
- `nis_design()` warns when annualized valid-design data represented in `DQTR`
  have fewer than four quarters, and explains how to exclude or separately
  reweight those years. It also warns when a 2015 cohort contains only
  ICD-9-coded quarters (Q1–Q3) or only the ICD-10-coded quarter (Q4), and
  informs when `DQTR` is missing so the 2015 split cannot be checked.
- `nis_cost()` records charge/CCR fields, CPI-U source and multipliers, base
  year, invalid CCR and missing charge counts, and adjusted-output meanings.
  Zero or negative CCR values now produce `NA` in `cost_adj` (previously zero
  CCR produced zero cost and negative CCR produced a negative cost); one
  informational message reports how many rows have missing or invalid CCR
  (`nis_design()` reports cohort rows only). Use
  `nis_cost_provenance()` on its result or the `nis_design()` survey design.
- Added `nis_prday_completeness()` for unweighted PRDAY completeness summaries
  by year and matched procedure slot.
- Added `nis_flag_pr_timing()` for procedure timing flags.
- Added `nis_attrition()` for cohort attrition summaries.
- `nis_open(engine = "duckdb")` provides an Arrow-backed DuckDB/dbplyr query
  path; `duckdb` and `dbplyr` are suggested dependencies. Flag and design
  helpers remain Arrow-only.
- Added `nis_audit_code_transition()` to summarize code-system transitions.
- Added `nis_flag_dx_position()` and `nis_dx_sensitivity()` for descriptive
  point estimates; these are not design-based estimates.
- `nis_suppress()` now accepts data frames with `count_col`, `weighted_cols`,
  and `by`, and supports single-dimension complementary suppression.
- `nis_suppress()` accepts `hospital_col` to mask cells based on fewer than two
  contributing hospitals; `nis_cell_counts()` computes unweighted discharge
  and year-scoped hospital counts from record-level data or an `nis_design()`.
- `nis_suppress()` now suppresses zero discharge counts at or below the
  threshold and rejects missing, non-finite, negative, or fractional
  data-frame count values.

# easyNIS 0.2.0

## Highlights

- Replaced the archived API with lazy annual Parquet opening, ICD-10 prefix
  flags, a domain survey design, HCUP labels, CPI-adjusted charges and costs,
  cell suppression, and an invented six-year example fixture.
- Added a Getting started guide, a guide to porting existing NIS studies, and
  an analyst workflow note.

## New features

- `nis_open()` supports 2012 onward. `nis_flag_dx()` and `nis_flag_pr()` match
  literal prefixes separately in each code slot; supplied prefixes ignore
  case, periods, and spaces, while stored codes are compared byte for byte
  without text normalization, so malformed UTF-8 cannot raise a matching
  error.
- Added experimental ICD-9 prefix flags with an explicit `system = "icd9"`
  option, metadata guards, and invented historical and split-2015 fixtures.
  ICD-10 remains the default.
- `nis_comorbidity()` adds AHRQ Elixhauser Refined condition flags and
  mortality/readmission index scores through the suggested `medicalcoder`
  package. It accepts a collected data frame or an `nis_design()` result.
- `nis_ccsr_codes()` reads a user-supplied HCUP DXCCSR or PRCCSR reference
  file (Excel via `readxl` or comma-separated) and returns ICD-10 codes in
  selected CCSR categories, optionally restricted to the default inpatient
  assignment. The codes can be passed to `nis_flag_dx()` or `nis_flag_pr()`.

## Survey design and weighting

- `nis_design()` reports aggregate exclusions for invalid design fields and
  affected years, stores the counts in the `nis_excluded` design attribute,
  and documents why rows with invalid `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or
  `DISCWT` cannot be represented in the supplied survey design. Exclusions
  happen before cohort filtering and do not imply zero population weight or
  unbiased estimates.
- `nis_design()` warns when charges are entirely missing for a year or when
  that year has hospitals but no cohort discharges. `annualize` divides by
  the number of distinct `YEAR` values, so a partial year counts as one.
- Added experimental `nis_reweight()` to multiply cohort survey weights while
  retaining placeholder rows. It preserves column labels when rebuilding
  designs, including after comorbidity scoring. Weights are matched by
  position; call the function once. Weighted totals after reweighting are not
  national counts, and its placeholder variance field does not provide survey
  variance estimation. An optional commented WeightIt/cobalt example is in
  the study template.

## Disclosure control

- `nis_suppress()` also masks the overall (`add_overall()`) cell in any row
  where a by-group cell is masked. It marks that secondary mask `Masked`,
  unless the overall cell is itself at or below the threshold.
- For `continuous2` statistic rows, suppression uses the displayed output
  column's non-missing count and errors when that count is missing, ambiguous,
  or non-finite. Other derivable cells, such as column totals across levels,
  are not masked; review tables before sharing.

## Study template

- Quarto study reports handle empty cohorts, one-level exposures, constant
  outcomes, and unusable model matrices with explicit status messages. Models
  use complete-case preflight; single-year reports omit the year adjustment,
  and DOCX trend tables display years without thousands separators.
- Report caches include study definitions, external data-root identity,
  report inputs, output format, and rendering dependencies.
- The template includes an optional, commented propensity-weighting example;
  both WeightIt and cobalt must be installed to use it.

## Documentation

- Added a Getting started guide covering file opening, flags, survey design,
  weighted tables, models, primary-cell suppression, and study scaffolding;
  runnable examples for exported helpers use invented fixtures, with the
  slower optional comorbidity example marked `donttest`.
- Added a vignette on porting existing NIS study code, a short tidyverse
  pipeline README, grouped pkgdown reference pages, and package citation
  metadata.
- Added issue templates, a privacy-aware pull request checklist, Contributor
  Covenant, security reporting guidance, and contributor instructions.
- Added CI workflows for linting, test coverage, and study-template rendering.
  The pkgdown site is published at <https://msaadasif.github.io/easyNIS/> on
  pushes to `main`.

## Experimental and unverified

- The placeholder-row survey method is experimental and must agree with the
  full-data design on estimates, standard errors, and degrees of freedom.
- ICD-9 support is experimental. Historical layout facts beyond the
  documented 2015 Q1–Q3/Q4 split are assumptions and have not been verified
  against official HCUP documentation or licensed data.
- NIS 2023 layout support is experimental and UNVERIFIED against official
  HCUP 2023 documentation and real 2023 data. It assumes `TOTCHG_2023`, the
  removal of `HOSP_REGION` and `HOSP_DIVISION`, and sequential `NIS_STRATUM`
  based on secondary notes. `nis_open()` accepts files without the geography
  columns and keeps `TOTCHG_2023` separate from `TOTCHG`; queries containing
  it receive a once-per-session warning because HCUP's national-estimate
  adjustment makes it incomparable with earlier-year charges. `nis_design()`
  and `nis_cost()` accept `charges = "TOTCHG_2023"` to opt in; pooling requires
  an explicit `mutate()`. Hospital and stratum IDs remain qualified by year.
- `nis_comorbidity()` is ICD-10 only, does not use present-on-admission
  values, and treats `I10_DX1` as the principal diagnosis. Its output is not
  expected to match the Stata-derived `ynel*` and `elixsum` columns. Rows
  without a usable `I10_DX*` code, including ICD-9-era discharges, receive
  `NA` and a warning rather than zeros.
- HCUP CCSR file layouts are UNVERIFIED; no CCSR content is bundled.
  Malformed single-quoted CSV rows and non-ICD-10 codes are rejected.
