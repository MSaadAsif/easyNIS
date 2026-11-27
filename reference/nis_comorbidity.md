# Add AHRQ Elixhauser comorbidity columns (experimental)

Reshapes the wide `I10_DX1`, `I10_DX2`, ... columns to one row per code
and scores them with
[`medicalcoder::comorbidities()`](http://www.peteredewitt.com/medicalcoder/reference/comorbidities.md).
For a lazy DuckDB query, the function projects the discharge keys and
diagnosis and POA fields, scores up to 25,000 discharges at a time in R,
then joins the scores back in DuckDB. Scores are materialized when this
function runs and live in a temporary table on the input connection. The
returned query remains lazy. Use stable keys and filters, and arrange
the result by key if you need a specific order. For a collected input,
row order is preserved. All code-to-condition mapping and index weights
come from the
[medicalcoder](https://CRAN.R-project.org/package=medicalcoder) package,
which ships the AHRQ Elixhauser Comorbidity Software Refined for
ICD-10-CM tables; easyNIS holds no clinical code lists. Install it with
`install.packages("medicalcoder")`.

## Usage

``` r
nis_comorbidity(.data, method = "elixhauser_ahrq_icd10", prefix = "cmrb_")
```

## Arguments

- .data:

  A data frame, a `tbl_svy` from
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
  or a lazy DuckDB query with `I10_DX1`, `I10_DX2`, ... columns. Lazy
  input requires non-missing, unique discharge keys (`YEAR` and
  `KEY_NIS` when `YEAR` is present, otherwise `KEY_NIS` alone). Keep
  `YEAR` when pooling years.

- method:

  A `medicalcoder` Elixhauser method name. The default,
  `"elixhauser_ahrq_icd10"`, is the union of every ICD-10 code AHRQ has
  listed since FY2022, which suits NIS years pooled across code-set
  updates. Use `"elixhauser_ahrq2022"` through `"elixhauser_ahrq2026"`
  to pin one AHRQ release.

- prefix:

  Prefix for the added columns. Existing columns are never replaced.

## Value

`.data` with one logical column per condition (`<prefix>hf`, ...),
`<prefix>n` (conditions flagged), `<prefix>any`, and the integer
`<prefix>mortality_index` and `<prefix>readmission_index` scores, using
the names and weights from `medicalcoder`. Rows with no usable `I10_DX*`
code are `NA` in all of them; see the Assumptions section.

## Details

The function is experimental: the default method and the assumptions
below remain pending scientific approval.

## Assumptions

- **Present on admission uses available diagnosis indicators.** Matching
  `DXPOAn` columns are aligned with `I10_DXn`; `Y` and `W` map to
  present, while `N` and `U` map to not present. Other values, including
  `1` and invalid UTF-8 values, are treated as unknown. `medicalcoder`
  applies its POA-exempt code table, based on AHRQ fiscal-year 2022
  through 2026 mappings; its exemption status is not adjusted for
  discharge date, so exempt-code results can differ slightly from AHRQ
  software across fiscal years. If a matching POA column is absent,
  easyNIS retains the existing assumption that diagnoses in that slot
  were present on admission and warns once per call. NIS release files
  lack POA indicators, so this assumption can count hospital-acquired
  conditions and affect both scores. AHRQ leaves 18 of 38 measures unset
  when POA inputs are unavailable and requires all 38 to calculate its
  indices. NIS Diagnosis and Procedure Groups files provide the
  available HCUP-derived measures beginning in 2019. See the [AHRQ User
  Guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/CMR-User-Guide-v2024-1.pdf).

- **Principal diagnosis** is `I10_DX1`. It is passed as the primary
  diagnosis, and `medicalcoder` applies the AHRQ rule for it (for
  example, a condition is not flagged from the principal diagnosis alone
  where AHRQ excludes it). Codes in `I10_DX2` onward are secondary. Only
  positive slot suffixes without leading zeros are recognized; malformed
  names such as `I10_DX0` and `I10_DX01` are ignored.

- **ICD-10 only.** Only the `I10_DX*` columns are read. A discharge with
  no usable `I10_DX*` code (all blank, missing or invalid UTF-8), such
  as an ICD-9 discharge from before October 2015, gets `NA` in every
  added column, and the function warns with the number of such rows. Do
  not treat those `NA` values as "no comorbidity".

- Codes are upper-cased with periods and spaces removed. Blank, missing
  or invalid UTF-8 codes are ignored, and an unmapped code adds no
  condition. A discharge with at least one usable but unmapped code gets
  zeros.

- Collected inputs are reshaped and scored in one pass. Use the DuckDB
  path to bound the size of the R batches for large cohorts.

## Differences from the Stata-derived columns

NIS studies often already carry `ynel*` indicators and `elixsum`,
derived in Stata from an earlier Elixhauser release. They are not
reproduced here and should not be expected to agree: the AHRQ Refined
software uses different condition definitions and categories (for
example, hypertension with and without heart failure or renal failure,
and separate liver, neurological and cancer subtypes), POA-dependent
flagging, and the principal-diagnosis rule above. Do not mix the two
sets of indicators in one model.

## Use with [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
needs the whole hospital-year frame to build placeholder rows, so do not
collect and enrich the cohort before calling it. Keep the diagnosis
columns in the design instead, then pass the design here:

    design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX"), starts_with("DXPOA")))
    design <- nis_comorbidity(design)

For a `tbl_svy` the function replaces `design$variables` and leaves the
design (clusters, strata, weights) untouched.

## See also

[Comorbidity
indicators](https://msaadasif.github.io/easyNIS/reference/articles/comorbidity.md).

## Examples

``` r
# Assign stable keys to this invented fixture. NIS files supply KEY_NIS.
discharges <- nis_open(nis_example(years = 2019)) |>
  dplyr::filter(AGE >= 18) |>
  dplyr::mutate(KEY_NIS = dplyr::row_number()) |>
  dplyr::compute()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4hTv13/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4hTv13/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
comorbid <- nis_comorbidity(discharges)
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
comorbid |> dplyr::select(AGE, cmrb_n, cmrb_any) |> head() |> dplyr::collect()
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
