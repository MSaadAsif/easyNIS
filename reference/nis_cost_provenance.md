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
nis_cost_provenance(.data)
```

## Arguments

- .data:

  A data frame returned by
  [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  or a survey design returned by
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Value

A list describing the charge and CCR fields, CPI-U source and base year,
annual multipliers, counts of invalid CCR and of missing or invalid
charges, and output meanings. Returns `NULL` when no cost adjustment
provenance is present.

## See also

[Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html).

Other outcomes and costs:
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md),
[`nis_comorbidity_condition_map()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity_condition_map.md),
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md),
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)

## Examples

``` r
charges <- nis_open(nis_example(years = 2019)) |>
  dplyr::select(YEAR, TOTCHG, CCR_NIS) |>
  dplyr::collect() |>
  nis_cost(dollars = 2024)
nis_cost_provenance(charges)$multipliers
#>   year multiplier
#> 1 2019   1.226992
```
