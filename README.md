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

`nis_open()` returns a lazy Arrow query. `nis_design()` collects cohort rows
and one placeholder per hospital-year without cohort cases. Later `filter()`
calls may only narrow the declared cohort. The placeholder variance method and
cost adjustment remain experimental pending scientific approval.

For AHRQ Elixhauser flags and index scores (experimental; needs the
`medicalcoder` package), keep the diagnosis columns in the design and pass it
to `nis_comorbidity()`:

```r
design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX")))
design <- nis_comorbidity(design)
```

Use `nis_example()` for invented offline data. Never commit licensed inputs,
private paths, local validation receipts, or record-derived output.
