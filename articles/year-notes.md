# Data notes by year

NIS layouts and coding systems vary across releases. Confirm field
definitions, missing-value conventions, weights, and design guidance in
the official documentation for every year in an analysis. The year
ranges below describe package handling, not exhaustive HCUP release
guidance.

## ICD coding systems

The package treats NIS diagnosis and procedure fields before 2016 as
ICD-9 and fields from 2016 onward as ICD-10. In 2015, Q1–Q3 use ICD-9
and Q4 uses ICD-10. The `system` argument selects which slot namespace a
flag examines. Missing version indicators rely on the supplied slot
schema; mixed-system shared columns are not supported. ICD-9 support
remains experimental.

## Quarter coverage and annualization

`nis_design(annualize = TRUE)` divides by the number of valid years, not
a fraction of annual coverage. A partial year counts as a full year. If
`DQTR` is available, the function warns about years without four
quarters and 2015 cohorts confined to one coding era. Decide whether to
exclude partial years or use another documented convention for the
estimand.

## Weights across the 2012 redesign

Trend analyses spanning the 2012 NIS redesign use `TRENDWT` for records
before 2012 and `DISCWT` for records from 2012 onward. easyNIS supports
2012 and later and does not apply pre-2012 trend weights. Follow the
[HCUP NIS trend weight
guidance](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp) when
planning analyses that span the redesign.

## 2023 layout notes

The package keeps `TOTCHG_2023` separate from earlier `TOTCHG` and notes
reported changes in geography and stratum fields. These 2023 layout
details are explicitly unverified against official 2023 documentation
and real 2023 files. Do not assume comparability or use these notes as a
substitute for checking the source documentation.

## Check availability in the fixture

[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
creates invented records for selected years to illustrate package
operations. Its rows are not a complete copy of annual layouts.

``` r

path <- nis_example(years = c(2015, 2019, 2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbKKYTo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbKKYTo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbKKYTo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path)
#> Experimental: years before 2016 store ICD-9-CM codes in DX1, PR1, ... slots.
#> ℹ Flag them with `system = "icd9"`; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4)
#>   slots.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbKKYTo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(YEAR) |> dplyr::collect()
#> # A tibble: 3 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
#> 2  2015    96
#> 3  2019    96
```

The summary confirms only that the synthetic fixture contains the
requested years. It does not validate a source year’s fields or
represent the real annual file.

## Common pitfalls

> **Common pitfalls**
>
> - Pooling years without year-scoped hospital and stratum identifiers.
> - Treating 2015 as a single-code-system year.
> - Assuming fields and coding rules remain unchanged across all
>   releases.
> - Treating package handling of a year as official HCUP documentation.

See [Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md),
[Code transitions and
sensitivity](https://msaadasif.github.io/easyNIS/articles/code-transitions.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
and
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
