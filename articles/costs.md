# Charges, costs, and provenance

## Convert charges to costs

Charges are not costs.
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
estimates hospital costs by multiplying charges by `CCR_NIS`, then
expresses both cost and charges in a selected reference-year dollar
using annual CPI-U indices.

``` r

charges <- nis_open(nis_example(years = 2019:2020)) |>
  dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHcLgzX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHcLgzX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHcLgzX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
adjusted <- nis_cost(charges, dollars = 2024)
head(adjusted[c("YEAR", "TOTCHG", "cost_adj", "charges_adj")])
#> # A tibble: 6 × 4
#>    YEAR TOTCHG cost_adj charges_adj
#>   <int>  <dbl>    <dbl>       <dbl>
#> 1  2019  14154    5036.      17367.
#> 2  2019  14189    5049.      17410.
#> 3  2019  14224    5061.      17453.
#> 4  2019  14259    5074.      17496.
#> 5  2019  14294    5086.      17539.
#> 6  2019  14329    5099.      17582.
```

`cost_adj` contains the estimated cost in 2024 dollars and `charges_adj`
contains adjusted charges. These are synthetic amounts intended only to
show the calculation.

## Check provenance

The direct result records the source fields, price index, base year,
multipliers, and invalid input counts.

``` r

nis_cost_provenance(adjusted)
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
#> 2 2020   1.212039
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
```

Missing or non-positive CCR values produce missing costs; the
corresponding adjusted charge can still be present. Describe the CCR and
inflation choices when reporting results.

`nis_design(..., dollars = 2024)` can add these adjusted values to the
survey design when `CCR_NIS` and the selected charge column are kept.

## Common pitfalls

> **Common pitfalls**
>
> - Calling inflation-adjusted charges “costs” without applying a CCR.
> - Treating missing or invalid CCR values as zero cost.
> - Combining `TOTCHG_2023` silently with earlier `TOTCHG`; its
>   definition is different and the package documents the 2023 layout as
>   unverified.
> - Dropping provenance attributes through later data-frame operations
>   before recording the adjustment method.

See
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md),
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md),
and
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
