# Charges, costs, and provenance

## Attach the annual cost-to-charge ratios

Keep the CCR file for each year alongside its matching NIS release. Read
the CCR file documentation for the hospital key and ratio to use, then
assemble one table with `YEAR`, `HOSP_NIS`, and the chosen ratio named
`CCR_NIS`. Hospital identifiers can repeat across years. Record the
source release and ratio field for each year.

| Input | Annual link to Core | How to attach it |
|----|----|----|
| Hospital characteristics | `YEAR`, `HOSP_NIS` | `nis_join_companion(..., component = "hospital")` |
| Severity measures | `YEAR`, `KEY_NIS` | `nis_join_companion(..., component = "severity")` |
| Cost-to-charge ratios | `YEAR`, `HOSP_NIS` | Attach the separately prepared CCR table |

The companion helper validates keys and requires a companion file for
each opened year. A Core row with no matching companion key gets missing
values. The CCR example projects only the fields needed for an in-memory
cost calculation. The invented ratio table intentionally omits 2020.

``` r

charges <- nis_open(nis_example(years = 2018:2020)) |>
  dplyr::select(YEAR, HOSP_NIS, TOTCHG) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpNxRinT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpNxRinT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
ccr <- data.frame(
  YEAR = rep(c(2018L, 2019L), each = 12L),
  HOSP_NIS = rep(1:12, times = 2L),
  CCR_NIS = rep(c(0.25, 0.30), each = 12L)
)
keys <- c("YEAR", "HOSP_NIS")
stopifnot(!anyNA(ccr[keys]), !anyDuplicated(ccr[keys]))
charges <- dplyr::left_join(
  charges, ccr, by = keys, relationship = "many-to-one", na_matches = "never"
)
```

Each discharge can match at most one ratio. The left join keeps the
unmatched year in the analysis data so its missing costs can be
reported.

## Convert charges to costs

[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
multiplies charges by `CCR_NIS` to estimate hospital costs. It expresses
both costs and charges in a selected reference-year dollar using annual
CPI-U indices.

``` r

adjusted <- nis_cost(charges, dollars = 2024)
#> Missing or invalid `CCR_NIS`; `cost_adj` is `NA` for these rows.
adjusted |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(missing_costs = sum(is.na(cost_adj)), discharges = dplyr::n())
#> # A tibble: 3 × 3
#>    YEAR missing_costs discharges
#>   <int>         <int>      <int>
#> 1  2018             0         96
#> 2  2019             0         96
#> 3  2020            96         96
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
#> 1 2018   1.249224
#> 2 2019   1.226992
#> 3 2020   1.212039
#> 
#> $rows_missing_or_invalid_ccr
#> [1] 96
#> 
#> $rows_missing_charges
#> [1] 0
#> 
#> $ccr_treatment
#> [1] "Missing, non-finite, zero, or negative CCR_NIS values produce NA cost_adj; charges_adj is retained."
#> 
#> $charges_treatment
#> [1] "Negative, missing, or non-finite charges produce NA charges_adj and cost_adj; zero charges are retained."
#> 
#> $output_types
#>                  charges_adj                     cost_adj 
#> "Inflation-adjusted charges" "Estimated cost via CCR_NIS"
```

Missing or non-positive CCR values produce missing costs; the
corresponding adjusted charge can still be present. Describe the CCR and
inflation choices when reporting results. Keep the annual CCR source and
key coverage with the analysis record. The provenance accessor records
the column used and the missing or invalid count for the data passed to
the calculation.

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
