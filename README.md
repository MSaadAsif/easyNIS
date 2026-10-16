# easyNIS

easyNIS provides a small, pipe-first workflow for HCUP National Inpatient
Sample data. The current increment supports 2016 and later ICD-10 years.

```r
library(easyNIS)

nis_open("path/to/nis", years = 2017:2022) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_design(
    heart_failure,
    keep = c(AGE, DIED, LOS, TOTCHG, CCR_NIS, APRDRG_RISK_MORTALITY)
  )
```

`nis_open()` returns a lazy Arrow query. `nis_design()` collects the cohort and
one placeholder row for each hospital-year without cohort cases so its survey
design retains the full hospital structure. After construction, `filter()` may
only narrow the declared cohort. This variance method remains experimental and
is checked against a full-data survey design.

Use `nis_example()` for an invented offline dataset. Never put licensed NIS
files or record-derived outputs in the repository. A Quarto study template and
study-folder generator are planned for a later increment.
