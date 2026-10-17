# Reweight a cohort survey design

Multiplies cohort discharge survey weights by supplied propensity
weights, retains the placeholder rows for hospital-years without cohort
discharges, and rebuilds the nested survey design. This experimental
method is intended for analysts who have validated their weighting
specification against a full-data reference design.

## Usage

``` r
nis_reweight(design, weights)
```

## Arguments

- design:

  A result of
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

- weights:

  Numeric weights aligned with the cohort rows of `design`, or an
  unquoted numeric column name in the design data. They are matched to
  rows by position, so take them from `design$variables` in that order
  (for example, fit the propensity model on `design$variables`) and do
  not reorder or subset the rows first.

## Value

A filtered [`srvyr::tbl_svy`](http://gdfe.co/srvyr/reference/tbl_svy.md)
survey design.

## Weighted totals

The result multiplies the discharge weights by `weights`, so
`survey_total()` and similar totals no longer estimate national
discharge counts. Use the result for ratios, means and model estimates,
and report national counts from the design before reweighting. Each call
multiplies the weights again, so call `nis_reweight()` once on the
result of
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md);
calling it on an already reweighted design compounds the weights.

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE))
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.

# Illustrative weights only; use weights from your own validated model
reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
srvyr::summarise(reweighted, weighted_total = srvyr::survey_total())
#> # A tibble: 1 × 2
#>   weighted_total weighted_total_se
#>            <dbl>             <dbl>
#> 1           127.              17.7
```
