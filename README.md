# easyNIS

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

Use `nis_example()` for invented offline data. Never commit licensed inputs,
private paths, local validation receipts, or record-derived output.

## Experimental 2012–2015 support

`nis_open()` accepts 2012 onward; earlier years are rejected. Use
`nis_flag_dx(..., system = "icd9")` and `nis_flag_pr(..., system = "icd9")`
for `DX1`, `DX2`, ... and `PR1`, `PR2`, ...; the default `"icd10"` checks
only `I10_DX*`/`I10_PR*`. Positions and prefix semantics are unchanged.
`nis_example(2012:2016)` demonstrates both eras using invented records.

The 2015 Q1–Q3 diagnosis/procedure file uses ICD-9 slots; Q4 uses separate
`I10_` slots, not shared `DX*`/`PR*` slots. Join each quarter-specific file
to Core by `KEY_NIS` before supplying annual Parquet data. Preserve the full
Core population and official names; easyNIS does not perform these joins.
Retain `DXVER` and `PRVER` (9 or 10): HCUP recommends `DXVER` to identify
the 2015 split because `DQTR` can be missing. Flags exclude non-missing
version indicators that disagree with the requested system, out-of-era
years, and incompatible 2015 quarters. Missing metadata relies on the
official slot namespace and missing inapplicable slots; reused/shared slots
are unsupported. A `FALSE` flag means not flagged in that system, not a
clinical assertion of absence.

For cross-era studies, supply independently justified diagnosis and procedure
prefix vectors for each system, call the flagger once per system, then combine
the resulting flags explicitly with `dplyr::mutate()`. There are no bundled
clinical code lists or crosswalks. October 1, 2015 is a coding discontinuity;
combining flags does not establish trend comparability. Common existing
`nis_label()` mappings and `nis_cost()` CPI-U values cover 2012–2015, but
ICD-9-specific derived indicators are not automatically mapped to ICD-10
indicators. Supply the correct annual CCR; no cost file is bundled.

The evidence level (verified versus assumed layout facts) and input
assumptions are recorded in `docs/ICD9-SUPPORT.md`.
