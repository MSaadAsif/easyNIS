# easyNIS

[![R-CMD-check](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml)

Pipe-friendly tools for NIS 2016+ ICD-10 data. Open annual Parquet directories
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
  `medicalcoder`).
- `nis_reweight()` multiplies cohort weights, for example by propensity
  weights, and keeps the placeholder rows.

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
