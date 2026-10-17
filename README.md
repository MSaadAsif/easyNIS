# easyNIS

[![R-CMD-check](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml)

Pipe-friendly tools for NIS 2012+ data, with experimental ICD-9 support through
September 2015 alongside the default ICD-10 workflow. Open annual Parquet directories
lazily, flag code prefixes, then build a survey design with `nis_design()`.

```r
# Install from GitHub once.
pak::pak("MSaadAsif/easyNIS")

library(easyNIS)

# Create a Quarto study folder and render analysis.qmd to HTML or DOCX.
nis_new_study("my-nis-study")

# Or start with the core analysis pipeline.
nis <- nis_open("path/to/nis", years = 2017:2022) |>
  nis_flag_dx(heart_failure = "I50", position = "principal")
design <- nis_design(
  nis, heart_failure,
  keep = c(AGE, FEMALE, DIED, LOS, TOTCHG, CCR_NIS)
)
gtsummary::tbl_svysummary(design, include = c(AGE, FEMALE, DIED))
survey::svyglm(DIED ~ AGE + factor(YEAR), design, family = quasibinomial())
```

`nis_open()` returns a lazy Arrow query. `nis_flag_dx()` and `nis_flag_pr()`
compare stored codes byte for byte (NIS codes are upper case without periods),
so they stay fast across all 40 diagnosis slots and cannot fail on malformed
text. `nis_design()` scans the design columns once, then collects cohort rows
and one placeholder per hospital-year without cohort cases. It excludes
discharges with a missing or non-positive `DISCWT`, `NIS_STRATUM`, or
`HOSP_NIS`, with a warning. Later `filter()` calls may only narrow the declared
cohort. The placeholder variance method and cost adjustment remain
experimental pending scientific approval.

Experimental helpers, each optional:

- `nis_ccsr_codes()` lists the ICD-10 codes in an HCUP CCSR category from the
  reference file you downloaded (readxl reads the Excel version).
- `nis_comorbidity()` adds AHRQ Elixhauser flags and index scores (needs
  `medicalcoder`). It is ICD-10 only; rows without an `I10_DX*` code get `NA`.
- `nis_reweight()` multiplies cohort weights, for example by propensity
  weights, and keeps the placeholder rows. Call it once; weighted totals are
  then no longer national counts.

```r
codes <- nis_ccsr_codes("DXCCSR-Reference-File-v2025-1.xlsx", "CIR019",
  default_only = TRUE)
nis <- nis_flag_dx(nis, heart_failure = codes, position = "principal")

# Keep the diagnosis columns in the design, then enrich it.
design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX")))
design <- nis_comorbidity(design)
design <- nis_reweight(design, runif(nrow(design$variables), 0.5, 1.5))
```

Start with `vignette("getting-started")` for an invented-data walkthrough from
opening files to a suppressed table and survey model. See `vignette("porting")`
for moving an existing NIS study to easyNIS.

Use `nis_example()` for invented offline data. Never commit licensed inputs,
private paths, local validation receipts, or record-derived output.

## Experimental 2012–2015 support

`nis_open()` accepts 2012 onward; earlier years are rejected. Use
`nis_flag_dx(..., system = "icd9")` and `nis_flag_pr(..., system = "icd9")`
for `DX1`, `DX2`, ... and `PR1`, `PR2`, ...; the default `"icd10"` checks
only `I10_DX*`/`I10_PR*`. Positions and prefix semantics are unchanged.
`nis_example(2012:2016)` demonstrates both eras using invented records.

2015 Q1–Q3 discharges are ICD-9 and Q4 discharges are ICD-10 (confirmed in
the NIS Introduction). The layout below is UNVERIFIED, assumed from
secondhand excerpts and not checked against HCUP files: ICD-9 codes in `DX*`/`PR*`, ICD-10 in
separate `I10_` slots, quarter-specific diagnosis/procedure files joined to
Core by `KEY_NIS`. easyNIS performs no joins; preserve the full Core
population and official names. Retain `DXVER` and `PRVER` (9 or 10), which
HCUP is understood to recommend over `DQTR` for the 2015 split (UNVERIFIED).
Flags exclude non-missing
version indicators that disagree with the requested system, out-of-era
years, and incompatible 2015 quarters. Missing metadata relies on the
official slot namespace and missing inapplicable slots; reused/shared slots
are unsupported. A `FALSE` flag means not flagged in that system, not a
clinical assertion of absence.

For cross-era studies, supply independently justified diagnosis and procedure
prefix vectors for each system, call the flagger once per system, then combine
the resulting flags explicitly with `dplyr::mutate()`. There are no bundled
clinical code lists or crosswalks. October 1, 2015 is a coding discontinuity;
combining flags does not establish trend comparability. `nis_cost()` CPI-U
values cover 2012–2015. `nis_label()` has been tested for 2012–2015 data only
for `PAY1` and `DIED`; other labels are UNVERIFIED for that era. Further,
ICD-9-specific derived indicators are not automatically mapped to ICD-10
indicators. Supply the correct annual CCR; no cost file is bundled.

The evidence level (verified versus assumed layout facts) and input
assumptions are recorded in `docs/ICD9-SUPPORT.md`.

NIS 2023 layout support is experimental and UNVERIFIED against official HCUP
2023 documentation and real 2023 data (none was available for testing).
`nis_open()` accepts the 2023 layout without `HOSP_REGION` and `HOSP_DIVISION`,
retains `HOSP_NIS` and `NIS_STRATUM`, and scopes both design identifiers by
`YEAR`. The 2023 `TOTCHG_2023` field is kept as its own column and `TOTCHG` is
never altered: HCUP adjusts `TOTCHG_2023` for states unavailable in 2023, so it
is not comparable with earlier-year charges. `nis_design()` and `nis_cost()`
use `TOTCHG` unless you opt in with `charges = "TOTCHG_2023"`, or pool
deliberately with `mutate(TOTCHG = coalesce(TOTCHG_2023, TOTCHG))`. Opening a
query with `TOTCHG_2023` warns once per session. Fields absent from
the 2023 layout stay optional, and `nis_label()` leaves 2023-only fields such as
`PL_NCHS2` and `TOTCHG_2023` unlabelled.
