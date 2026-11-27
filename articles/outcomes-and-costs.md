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
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpqSIuMC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpqSIuMC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
outcomes <- nis |> nis_outcomes()
outcomes |> select(in_hospital_death, los_days) |> head() |> collect()
#> # A tibble: 6 × 2
#>   in_hospital_death los_days
#>   <lgl>                <dbl>
#> 1 FALSE                    2
#> 2 FALSE                    3
#> 3 FALSE                    4
#> 4 FALSE                    5
#> 5 FALSE                    6
#> 6 FALSE                    7
```

`DIED` defines in-hospital death. `DISPUNIFORM` describes where the
patient went at discharge. `los_days` comes from `LOS`. Keep all three
source fields when calling
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md).

``` r

scored <- outcomes |> nis_comorbidity(method = "charlson_quan2005")
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
scored |> select(starts_with("cmrb_")) |> head(3) |> collect()
#> # A tibble: 3 × 20
#>   cmrb_aidshiv cmrb_mal cmrb_cebvd cmrb_copd cmrb_chf cmrb_dem cmrb_dmc cmrb_dm
#>   <lgl>        <lgl>    <lgl>      <lgl>     <lgl>    <lgl>    <lgl>    <lgl>  
#> 1 FALSE        FALSE    FALSE      FALSE     TRUE     FALSE    FALSE    FALSE  
#> 2 FALSE        FALSE    FALSE      FALSE     FALSE    FALSE    FALSE    TRUE   
#> 3 FALSE        FALSE    FALSE      FALSE     FALSE    FALSE    FALSE    TRUE   
#> # ℹ 12 more variables: cmrb_hp <lgl>, cmrb_mld <lgl>, cmrb_msld <lgl>,
#> #   cmrb_mst <lgl>, cmrb_mi <lgl>, cmrb_pud <lgl>, cmrb_pvd <lgl>,
#> #   cmrb_rnd <lgl>, cmrb_rhd <lgl>, cmrb_n <int>, cmrb_any <lgl>,
#> #   cmrb_cci <int>
```

Score before
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
while the diagnosis slots are available and DuckDB can still apply the
mappings. Choose the method and code system for your study period. The
Charlson example needs `medicalcoder`. The bundled
`"elixhauser_ahrq2027"` method has no `medicalcoder` dependency.

## Estimate costs in a common dollar year

``` r

charges <- outcomes |> select(YEAR, TOTCHG, CCR_NIS) |> collect()
costs <- nis_cost(charges, dollars = 2020)
nis_cost_provenance(costs)
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
#> [1] 2020
#> 
#> $multipliers
#>   year multiplier
#> 1 2019   1.012337
#> 2 2020   1.000000
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
#> $charges_treatment
#> [1] "Negative, missing, or non-finite charges produce NA charges_adj and cost_adj; zero charges are retained."
#> 
#> $output_types
#>                  charges_adj                     cost_adj 
#> "Inflation-adjusted charges" "Estimated cost via CCR_NIS"
costs |>
  transmute(YEAR, billed = TOTCHG, charges_adj,
            cost_at_discharge = TOTCHG * CCR_NIS, cost_adj) |>
  head()
#> # A tibble: 6 × 5
#>    YEAR billed charges_adj cost_at_discharge cost_adj
#>   <int>  <dbl>       <dbl>             <dbl>    <dbl>
#> 1  2019  14154      14329.             4105.    4155.
#> 2  2019  14189      14364.             4115.    4166.
#> 3  2019  14224      14399.             4125.    4176.
#> 4  2019  14259      14435.             4135.    4186.
#> 5  2019  14294      14470.             4145.    4196.
#> 6  2019  14329      14506.             4155.    4207.
```

Join the year-specific HCUP cost-to-charge ratio before estimating costs
if the data lack `CCR_NIS`. `charges_adj` is the adjusted billed amount.
`cost_adj` applies the hospital ratio to estimate costs. Missing or
invalid ratios yield missing costs. CPI-U tracks general consumer price
inflation. It does not track hospital-specific input prices. When
comparing with a legacy result, check its charge field, CCR source,
price index, and dollar year. Keep the provenance alongside both cost
and charge results. [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)

If
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
keeps both `TOTCHG` and `CCR_NIS`, it adds `charges_adj` and `cost_adj`
in dollars of the latest included year by default. Use
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
to set a common dollar year across separate analyses and retain the
provenance with your results.
