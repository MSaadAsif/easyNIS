# Comorbidity indicators

[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
uses the optional `medicalcoder` package to apply its AHRQ Elixhauser
ICD-10-CM mapping. easyNIS does not distribute clinical code lists. This
computation is experimental and its assumptions need scientific review.

## Score a collected cohort

The function accepts a collected data frame with `I10_DX1`, `I10_DX2`,
and other diagnosis columns.

``` r

discharges <- nis_open(nis_example(years = 2019)) |>
  dplyr::filter(AGE >= 18) |>
  dplyr::select(AGE, dplyr::starts_with("I10_DX")) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpLrDgVy/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpLrDgVy/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
scored <- nis_comorbidity(discharges)
head(scored[c("AGE", "cmrb_n", "cmrb_any")])
#> # A tibble: 6 × 3
#>     AGE cmrb_n cmrb_any
#>   <dbl>  <int> <lgl>   
#> 1    28      1 TRUE    
#> 2    35      1 TRUE    
#> 3    42      1 TRUE    
#> 4    49      0 FALSE   
#> 5    56      1 TRUE    
#> 6    63      1 TRUE
```

The added columns report the number of flagged conditions and whether
any were flagged. Values are computed from invented codes. Rows without
usable ICD-10 codes have missing results rather than “no comorbidity.”

## Add scores after design construction

If an analysis uses
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
keep diagnosis columns in the design and pass the design to
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md).
This preserves the design object.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpLrDgVy/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpLrDgVy/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure,
  keep = c(AGE, dplyr::starts_with("I10_DX"))
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
scored_design <- nis_comorbidity(design)
head(scored_design$variables[c("AGE", "cmrb_n", "cmrb_any")])
#> # A tibble: 6 × 3
#>     AGE cmrb_n cmrb_any
#>   <dbl>  <int> <lgl>   
#> 1    28      1 TRUE    
#> 2    35      1 TRUE    
#> 3    49      0 FALSE   
#> 4    56      1 TRUE    
#> 5    70      1 TRUE    
#> 6    77      1 TRUE
```

The survey design fields remain the same while the analysis variables
gain comorbidity indicators.

## Common pitfalls

> **Common pitfalls**
>
> - The function uses ICD-10 slots only; pre-October 2015 ICD-9 records
>   cannot be scored and receive missing values.
> - NIS includes diagnosis present-on-admission fields (`DXPOA1`,
>   `DXPOA2`, and so on), but this helper does not use them: it passes
>   every diagnosis code as present on admission (`poa = 1`). AHRQ’s
>   refined Elixhauser method requires POA for 18 of its 38 measures, so
>   this approximation can count a complication that arose during the
>   stay as pre-existing for a POA-sensitive measure.
> - Do not assume agreement with older Stata-derived `ynel*` and
>   `elixsum` fields; definitions and versions differ.

See
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
and [Data notes by
year](https://msaadasif.github.io/easyNIS/articles/year-notes.md).
