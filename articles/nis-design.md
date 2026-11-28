# How the NIS survey design works

``` r

library(easyNIS)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
library(srvyr)
#> 
#> Attaching package: 'srvyr'
#> The following object is masked from 'package:stats':
#> 
#>     filter

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
cohort <- nis_design(nis, cohort = heart_failure, keep = LOS)

full <- nis |>
  select(nis_vars_design(), heart_failure, LOS) |>
  collect() |>
  mutate(psu = interaction(YEAR, HOSP_NIS),
         stratum = interaction(YEAR, NIS_STRATUM)) |>
  as_survey_design(ids = psu, strata = stratum, weights = DISCWT, nest = TRUE) |>
  filter(heart_failure)

summarise(cohort, total = survey_total(), mean_los = survey_mean(LOS))
#> # A tibble: 1 × 4
#>   total total_se mean_los mean_los_se
#>   <dbl>    <dbl>    <dbl>       <dbl>
#> 1  125.     17.3     5.66       0.229
summarise(full, total = survey_total(), mean_los = survey_mean(LOS))
#> # A tibble: 1 × 4
#>   total total_se mean_los mean_los_se
#>   <dbl>    <dbl>    <dbl>       <dbl>
#> 1  125.     17.3     5.66       0.229
```

The example uses invented data. The two calculations give the same
totals, means, and standard errors. The second fits the full sample in R
so you can check the cohort calculation directly.

## Hospitals in the variance calculation

Since 2012, the NIS has sampled discharges across hospitals in its
sampling frame. For variance estimation, easyNIS uses the
with-replacement ultimate-cluster approximation described in HCUP
Methods Series 2015-09. `HOSP_NIS` identifies the hospital cluster,
`NIS_STRATUM` identifies the stratum, and `DISCWT` weights discharges.
The approximation uses variation among hospital contributions within a
stratum. It uses no finite population correction. [HCUP variance
guidance](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp)

## Why zero-contribution hospitals matter

For a domain total, a hospital with no cohort discharges contributes
zero. Omitting it changes both the sample size for the stratum and the
variation of hospital totals. Keeping one zero-domain placeholder per
such hospital preserves those quantities.

The same argument applies to linearized scores for means, ratios, and
supported survey-weighted regression models. Non-domain discharges have
zero scores, so their individual records can be replaced by a zero
contribution for the hospital. Under this design and the same singleton
policy, the placeholder calculation is exact for these estimators. It
preserves the full-sample domain calculation under the stated variance
approximation.

## Why identifiers include the year

A hospital or stratum number can recur across years. easyNIS identifies
strata and clusters within each year so reuse of a number does not
combine sampling units. Original discharge weights represent the pooled
period. For average annual totals, check coverage before [annualizing
the
weights](https://msaadasif.github.io/easyNIS/articles/how-easynis-works.html#decide-how-to-pool-years).
