# Add CCSR categories to a NIS query

Matches complete ICD-10 codes in DuckDB and preserves one row per input
row. The `"any"` and `"principal"` positions produce a list column of
distinct, sorted categories. For inpatient diagnoses, `"default"`
produces the single HCUP default category for `I10_DX1`.

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

AHRQ's CCSR mappings are cumulative from October 2015. For each
discharge year, the default is the earliest bundled fiscal year covering
that entire calendar year, using the latest bundled revision of that
fiscal year. The bundled DXCCSR and PRCCSR v2025.1 cover Q4 2015 and
2016–2024 by this rule. Pinning `"2025.1"` also covers Q1–Q3 2025 when
`DQTR` is available. A fixed version can keep category definitions
constant across years.

ICD-9 discharges and rows outside the selected release's coverage get
missing results. Within coverage, a row without any matching codes gets
an empty list, or `NA` for its inpatient default category. Match results
use the release as published and do not establish whether an individual
code was valid on a specific discharge date.

## See also

[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[AHRQ HCUP
CCSR](https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp).

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpWkWQQQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpWkWQQQ/duckdb
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
