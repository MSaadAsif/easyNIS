# Add CCSR categories to a NIS query

Add Clinical Classifications Software Refined categories to a DuckDB
query.

## Usage

``` r
nis_add_ccsr(
  .data,
  categories = NULL,
  type = c("dx", "pr"),
  position = c("any", "principal", "default"),
  version = NULL,
  name = "ccsr"
)
```

## Arguments

- .data:

  Lazy DuckDB query with `YEAR` and canonical `I10_DX<n>` or `I10_PR<n>`
  slots. When present, `DQTR` identifies Q4 2015 and `DXVER` or `PRVER`
  must be 10 or missing for ICD-10 records.

- categories:

  Optional character vector of CCSR category codes, such as `"CIR019"`,
  to keep. The default returns all assigned categories.

- type:

  `"dx"` for diagnoses or `"pr"` for procedures.

- position:

  `"any"` checks all slots, `"principal"` checks slot 1, and `"default"`
  returns the inpatient principal diagnosis default.

- version:

  Optional bundled version, such as `"2025.1"`, to use across years.

- name:

  Name of the new column.

## Value

A lazy DuckDB query with one additional column.

## Details

Matches full ICD-10 codes. The any-position and principal modes return
distinct categories as a list. The diagnosis default mode returns one
inpatient principal diagnosis category.

The bundled 2025.1 mappings cover Q4 2015 and calendar years 2016
through 2024. Pin a version to use the same categories across years.
Out-of-coverage discharges receive missing results. Within coverage,
unmatched discharges receive an empty list or a missing default
category.

## See also

[Define and save a
cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html),
[Define and save a
cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[AHRQ HCUP
CCSR](https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp).

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpmk5GyP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpmk5GyP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |>
  nis_add_ccsr(position = "default") |>
  dplyr::count(ccsr) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   ccsr       n
#>   <chr>  <dbl>
#> 1 CIR019   108
#> 2 RSP002    84
```
