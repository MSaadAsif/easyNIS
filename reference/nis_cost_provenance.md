# Read cost adjustment provenance

Returns the metadata recorded by
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
or
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
when cost adjustment was requested. Data frame operations may drop
custom attributes; call this on the direct
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
result or on the survey design returned by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Usage

``` r
nis_cost_provenance(x)
```

## Arguments

- x:

  A data frame returned by
  [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  or a survey design returned by
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Value

A list describing the charge and CCR fields, CPI-U source and base year,
annual multipliers, invalid CCR and missing charge counts, and output
meanings. Returns `NULL` when no cost adjustment provenance is present.

## See also

[Charges, costs, and
provenance](https://msaadasif.github.io/easyNIS/reference/articles/costs.md).

Other costs:
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)

## Examples

``` r
charges <- nis_open(nis_example(years = 2019)) |>
  dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
  dplyr::collect() |>
  nis_cost(dollars = 2024)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpe41Z1U/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpe41Z1U/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_cost_provenance(charges)
#> $charge_field
#> [1] "TOTCHG"
#> 
#> $ccr_field
#> [1] "CCR_NIS"
#> 
#> $inflation_index
#> [1] "CPI-U All items, U.S. city average (annual average)"
#> 
#> $inflation_index_source
#> [1] "U.S. Bureau of Labor Statistics, CPI-U All items, U.S. city average, not seasonally adjusted, series CUUR0000SA0; annual averages"
#> 
#> $base_year
#> [1] 2024
#> 
#> $multipliers
#>   year multiplier
#> 1 2019   1.226992
#> 
#> $rows_missing_or_invalid_ccr
#> [1] 0
#> 
#> $rows_missing_charges
#> [1] 0
#> 
#> $ccr_treatment
#> [1] "Missing, non-finite, zero, or negative CCR_NIS values produce NA cost_adj; charges_adj is retained."
#> 
#> $output_types
#>                  charges_adj                     cost_adj 
#> "Inflation-adjusted charges" "Estimated cost via CCR_NIS" 
#> 
```
