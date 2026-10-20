# Adjust NIS charges and costs to a reference dollar year

Adjust NIS charges and costs to a reference dollar year

## Usage

``` r
nis_cost(data, dollars, charges = "TOTCHG")
```

## Arguments

- data:

  A collected data frame with `YEAR`, the `charges` column, and
  `CCR_NIS`. Lazy Arrow and DuckDB queries must be collected first.

- dollars:

  Reference dollar year, from 2012 through 2024.

- charges:

  Name of the total-charge column. Defaults to `"TOTCHG"`. Use
  `"TOTCHG_2023"` only knowingly: HCUP adjusts that field for states
  missing from 2023, so it is not comparable to earlier-year `TOTCHG`,
  and it is missing for earlier years.

## Value

`data` with `cost_adj` and `charges_adj` in `dollars` USD. The in-memory
data frame has `nis_cost_provenance` metadata; retrieve it with
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md).

## Examples

``` r
charges <- nis_open(nis_example(years = 2019:2020)) |>
  dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
  dplyr::collect()
head(nis_cost(charges, dollars = 2024))
#> # A tibble: 6 × 5
#>    YEAR TOTCHG CCR_NIS cost_adj charges_adj
#>   <int>  <dbl>   <dbl>    <dbl>       <dbl>
#> 1  2019  14154    0.29    5036.      17367.
#> 2  2019  14189    0.29    5049.      17410.
#> 3  2019  14224    0.29    5061.      17453.
#> 4  2019  14259    0.29    5074.      17496.
#> 5  2019  14294    0.29    5086.      17539.
#> 6  2019  14329    0.29    5099.      17582.
```
