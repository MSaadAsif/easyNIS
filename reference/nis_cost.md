# Adjust NIS charges and costs to a reference dollar year

Express charges and estimated hospital costs in a common dollar year.
Invalid charges produce missing adjusted charges and costs. Invalid
cost-to-charge ratios produce missing costs. Use
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md)
to inspect the annual multipliers and audit missing values.

## Usage

``` r
nis_cost(.data, dollars, charges = "TOTCHG")
```

## Arguments

- .data:

  A collected data frame with `YEAR`, the `charges` column, and
  `CCR_NIS`. Lazy DuckDB queries must be collected first.

- dollars:

  Reference dollar year, from 2012 through 2024.

- charges:

  Name of the total-charge column. Defaults to `"TOTCHG"`. Negative,
  missing, and non-finite values are invalid; zero is retained. Use
  `"TOTCHG_2023"` only knowingly: HCUP adjusts that field for states
  missing from 2023, so it is not comparable to earlier-year `TOTCHG`,
  and it is missing for earlier years.

## Value

`.data` with `cost_adj` and `charges_adj` in `dollars` USD. The
in-memory data frame has `nis_cost_provenance` metadata; retrieve it
with
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md).

## See also

[Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html).

Other outcomes and costs:
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md),
[`nis_comorbidity_condition_map()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity_condition_map.md),
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md),
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)

## Examples

``` r
charges <- nis_open(nis_example(years = 2019:2020)) |>
  dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
  dplyr::collect()
nis_cost(charges, dollars = 2024) |>
  dplyr::summarise(mean_cost = mean(cost_adj), .by = YEAR)
#> # A tibble: 2 × 2
#>    YEAR mean_cost
#>   <int>     <dbl>
#> 1  2019     5366.
#> 2  2020     5301.
```
