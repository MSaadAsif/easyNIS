# easyNIS

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

Use `nis_example()` for invented offline data. Never commit licensed inputs,
private paths, local validation receipts, or record-derived output.

NIS 2023 layout support is experimental and UNVERIFIED against official HCUP
2023 documentation and real 2023 data (none was available for testing).
`nis_open()` accepts the 2023 layout without `HOSP_REGION` and `HOSP_DIVISION`,
retains `HOSP_NIS` and `NIS_STRATUM`, and scopes both design identifiers by
`YEAR`. The 2023 `TOTCHG_2023` field is kept as its own column and `TOTCHG` is
never altered: HCUP adjusts `TOTCHG_2023` for states unavailable in 2023, so it
is not comparable with earlier-year charges. `nis_design()` and `nis_cost()`
use `TOTCHG` unless you opt in with `charges = "TOTCHG_2023"`, or pool
deliberately with `mutate(TOTCHG = coalesce(TOTCHG_2023, TOTCHG))`. Opening a
query with `TOTCHG_2023` warns once per session. The removed `RACE` field is
optional, and the coarser `PL_NCHS2` field is labelled when present.
