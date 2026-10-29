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
  dplyr::select(AGE, dplyr::starts_with("I10_DX"), dplyr::starts_with("DXPOA")) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9sketD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9sketD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
scored <- nis_comorbidity(discharges)
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
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
#> ℹ /tmp/Rtmp9sketD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9sketD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure,
  keep = c(AGE, dplyr::starts_with("I10_DX"), dplyr::starts_with("DXPOA"))
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
scored_design <- nis_comorbidity(design)
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
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
> - When matching diagnosis present-on-admission fields (`DXPOA1`,
>   `DXPOA2`, and so on) are available, the helper aligns them with the
>   diagnosis slots. `Y` and `W` count as present on admission; `N` and
>   `U` do not. Other values are unknown, and POA-exempt codes are
>   handled by `medicalcoder`. If a matching POA field is absent, the
>   corresponding diagnosis is assumed present to preserve behavior for
>   years and inputs without POA fields. A warning names the affected
>   diagnosis slots; their POA-dependent comorbidities may include
>   conditions acquired in hospital. AHRQ’s refined software requires
>   POA to assign 18 of 38 measures and returns missing results when
>   required POA information is unavailable ([AHRQ User
>   Guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/CMR-User-Guide-v2024-1.pdf)).
>   `medicalcoder` uses an exemption mapping covering AHRQ fiscal years
>   2022–2026, with POA-exemption status consistent across those
>   releases. It does not adjust exemptions for discharge date, so
>   exempt-code results can differ slightly from AHRQ software across
>   fiscal years. As POA availability varies, results can differ between
>   inputs with and without those fields.
> - Do not assume agreement with older Stata-derived `ynel*` and
>   `elixsum` fields; definitions and versions differ.

See
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
and [Data notes by
year](https://msaadasif.github.io/easyNIS/articles/year-notes.md).
