# Add comorbidity indicators and scores (experimental)

Add Elixhauser or Charlson comorbidity flags and scores.

## Usage

``` r
nis_comorbidity(
  .data,
  method = "elixhauser_ahrq_icd10",
  prefix = "cmrb_",
  count_distinct = FALSE,
  exclude_conditions = character()
)
```

## Arguments

- .data:

  A data frame, a `tbl_svy` from
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
  or a lazy DuckDB query. Lazy input requires non-missing, unique
  `KEY_NIS`, or unique pairs of `YEAR` and `KEY_NIS` when `YEAR` is
  present. Keep `YEAR` when pooling years.

- method:

  Comorbidity definition. The default `"elixhauser_ahrq_icd10"` uses the
  medicalcoder ICD-10-CM union. `"elixhauser_ahrq2022"` through
  `"elixhauser_ahrq2027"` select a specific release. Use
  `"charlson_quan2005"` for Quan coding with original Charlson weights,
  `"charlson_quan2011"` for the same coding with Quan 2011 weights, and
  `"charlson_deyo1992"` for Deyo ICD-9-CM coding with original weights.
  `"elixhauser_quan2005"` uses Quan ICD-9-CM or ICD-10 coding and legacy
  AHRQ weights. `"elixhauser_ahrq_web"` and
  `"elixhauser_elixhauser1998"` replicate medicalcoder's legacy ICD-9
  code-based algorithms. All methods except `"elixhauser_ahrq2027"`
  require the medicalcoder package.

- prefix:

  Prefix for the added columns. Choose a prefix that does not collide
  with an existing name.

- count_distinct:

  Set to `TRUE` to add the integer count `<prefix>n_distinct`. Each
  condition represented by any true flag counts once, using
  [`nis_comorbidity_condition_map()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity_condition_map.md).
  A discharge with usable codes and no included conditions receives
  zero. A discharge without usable codes receives `NA`.

- exclude_conditions:

  Character vector of unprefixed condition IDs to omit from the distinct
  count. Requires `count_distinct = TRUE` when nonempty. Exclusions
  affect only the distinct count.

## Value

`.data` with logical condition flags and `<prefix>any`, the integer
count `<prefix>n`, and either `<prefix>mortality_index` and
`<prefix>readmission_index` (Elixhauser) or `<prefix>cci` (Charlson).
Charlson scores are based on diagnoses and any mapped procedures without
an age adjustment.

## Coding and present on admission

Keep the applicable diagnosis slots and use character codes to retain
ICD-9 leading zeros. Scoring excludes the principal diagnosis. Deyo can
also use mapped ICD-9 procedure codes. A discharge with usable codes and
no matches receives zero scores. A discharge without usable codes
receives missing scores.

The NIS has no diagnosis-level present-on-admission (POA) fields. When a
matching field is absent, the POA-aware methods assume that diagnosis
was present on admission. AHRQ Refined Elixhauser leaves the
POA-dependent measures unset when POA is unavailable.

Score before
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
to keep the work in DuckDB, or retain the diagnosis and available POA
columns in an existing design.

## See also

[Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html),
[Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html).

Other comorbidity:
[`nis_comorbidity_condition_map()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity_condition_map.md)

## Examples

``` r
nis <- nis_open(nis_example(2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbD2WgP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbD2WgP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_comorbidity(nis, method = "elixhauser_ahrq2027") |>
  dplyr::count(cmrb_mortality_index) |>
  dplyr::collect()
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
#> # A tibble: 2 × 2
#>   cmrb_mortality_index     n
#>                  <int> <dbl>
#> 1                   14    23
#> 2                    0    73
```
