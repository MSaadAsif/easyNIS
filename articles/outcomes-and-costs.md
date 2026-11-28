# Derive outcomes, comorbidities, and costs

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

## Add outcomes and score comorbidities

> The NIS has no diagnosis-level present-on-admission fields (`DXPOA`).
> The default Elixhauser method assumes diagnoses were present on
> admission. That assumption differs from the AHRQ Refined method with
> known POA. Document it if you use these scores for risk adjustment.

``` r

nis <- nis_open(nis_example(years = 2019:2020))
outcomes <- nis |> nis_outcomes()
outcomes |> count(in_hospital_death) |> collect()
#> # A tibble: 2 × 2
#>   in_hospital_death     n
#>   <lgl>             <dbl>
#> 1 FALSE               188
#> 2 TRUE                  4
```

`DIED` defines in-hospital death. `DISPUNIFORM` describes where the
patient went at discharge. `los_days` comes from `LOS`. Keep all three
source fields when calling
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md).

Install `medicalcoder` to run this Charlson example. Expect a warning
about absent present-on-admission fields. The method assumes the
diagnoses were present on admission.

``` r

scored <- outcomes |> nis_comorbidity(method = "charlson_quan2005")
#> Warning: No matching POA column for some diagnosis slots. Assuming present on admission.
#> ℹ POA-dependent scores may include conditions acquired in hospital.
scored |> count(cmrb_n) |> arrange(cmrb_n) |> collect()
#> # A tibble: 2 × 2
#>   cmrb_n     n
#>    <int> <dbl>
#> 1      0    38
#> 2      1   154
```

Score before
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
while the diagnosis slots are available and DuckDB can still apply the
mappings. Choose the method and code system for your study period. The
bundled `"elixhauser_ahrq2027"` method has no `medicalcoder` dependency.

Set `count_distinct = TRUE` to add the integer column `cmrb_n_distinct`.
The distinct count counts each condition represented by the output flags
once. For example, the refined Elixhauser flag for hypertension with
heart failure and severe renal failure represents three conditions, even
when separate flags for those conditions are also true. Diabetes and
other severity variants of the same condition share an ID. `cmrb_n`
still reports the method’s own category count.

``` r

method <- "elixhauser_ahrq2027"
condition_map <- nis_comorbidity_condition_map(method)
condition_map |> filter(condition == "diabetes")
#>           output condition
#> 1   cmrb_diab_cx  diabetes
#> 2 cmrb_diab_uncx  diabetes

outcomes |>
  nis_comorbidity(method, count_distinct = TRUE, exclude_conditions = "diabetes") |>
  count(cmrb_n, cmrb_n_distinct) |>
  arrange(cmrb_n, cmrb_n_distinct) |>
  collect()
#> Warning: No matching POA column for some diagnosis slots. Assuming present on admission.
#> ℹ POA-dependent scores may include conditions acquired in hospital.
#> # A tibble: 3 × 3
#>   cmrb_n cmrb_n_distinct     n
#>    <int>           <int> <dbl>
#> 1      0               0    38
#> 2      1               0   108
#> 3      1               1    46
```

Use IDs from the map to exclude conditions that your analysis handles
separately. The count uses the flags emitted by the chosen method and
inherits their present-on-admission assumptions. Exclusions affect only
the distinct count. A discharge without usable codes has a missing
count, and a discharge with usable codes and no included conditions has
a count of zero.

## Estimate costs in a common dollar year

``` r

charges <- outcomes |> select(YEAR, TOTCHG, CCR_NIS) |> collect()
costs <- nis_cost(charges, dollars = 2020)
nis_cost_provenance(costs)$multipliers
#>   year multiplier
#> 1 2019   1.012337
#> 2 2020   1.000000
costs |>
  summarise(mean_charge = mean(charges_adj), mean_cost = mean(cost_adj), .by = YEAR)
#> # A tibble: 2 × 3
#>    YEAR mean_charge mean_cost
#>   <int>       <dbl>     <dbl>
#> 1  2019      15009.     4428.
#> 2  2020      14828.     4374.
```

Join the year-specific HCUP cost-to-charge ratio before estimating costs
if the data lack `CCR_NIS`. `charges_adj` is the adjusted billed amount.
`cost_adj` applies the hospital ratio to estimate costs. Missing or
invalid ratios yield missing costs. CPI-U tracks general consumer price
inflation. It does not track hospital-specific input prices. When
comparing with a legacy result, check its charge field, CCR source,
price index, and dollar year. Keep the provenance alongside both cost
and charge results. The means here describe the invented sample. Use the
survey design for national estimates. [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)

If
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
keeps both `TOTCHG` and `CCR_NIS`, it adds `charges_adj` and `cost_adj`
in dollars of the latest included year by default. Use
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
to set a common dollar year across separate analyses and retain the
provenance with your results.
