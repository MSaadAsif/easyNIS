# Make tables and fit survey models

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

## Summarize the cohort

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpOgOaHF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpOgOaHF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, AGE >= 18, keep = c(AGE, LOS, DIED, RACE, heart_failure))
#> Preparing the cohort survey design.

design |>
  group_by(heart_failure) |>
  summarise(
    sampled = unweighted(n()),
    discharge_total = survey_total(),
    mean_los = survey_mean(LOS, na.rm = TRUE, vartype = c("se", "ci"))
  )
#> # A tibble: 2 × 8
#>   heart_failure sampled discharge_total discharge_total_se mean_los mean_los_se
#>   <lgl>           <int>           <dbl>              <dbl>    <dbl>       <dbl>
#> 1 FALSE              84            104                19.9     5.38       0.273
#> 2 TRUE              108            125.               17.3     5.66       0.229
#> # ℹ 2 more variables: mean_los_low <dbl>, mean_los_upp <dbl>
```

`sampled` counts records. `discharge_total` estimates the number of
discharges across both years. Set the denominator for each statistic
before reviewing its disclosure risk.

Install `gtsummary` and `cardx` for the survey table, and
`broom.helpers` for the regression table below.

``` r

library(gtsummary)

table_design <- design |> select(YEAR, HOSP_NIS, heart_failure, AGE, LOS, DIED)
tbl_svysummary(table_design, by = heart_failure, include = c(AGE, LOS, DIED)) |>
  nis_suppress()
```

[TABLE]

Select the table’s variables before building it. Keep `YEAR` and
`HOSP_NIS` so suppression can count contributing hospital-years. Reuse
the original design for models that need additional variables.

## Fit a model and estimate a contrast

``` r

fit <- survey::svyglm(LOS ~ heart_failure + AGE, design = design)
survey::svycontrast(fit, c(heart_failureTRUE = 1))
#>          contrast     SE
#> contrast  0.17863 0.4205
tbl_regression(fit)
```

[TABLE]

``` r

nobs(fit)
#> [1] 192
```

The contrast estimates the adjusted difference in mean length of stay.
Use the fitted model’s count to report the number of sampled discharges.
The N returned through
[`tbl_regression()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_regression.html)
for a `svyglm()` can be weighted. Check the fitted sample before
labeling or reporting N. [Check
disclosure](https://msaadasif.github.io/easyNIS/articles/disclosure.md)

## Apply prespecified reweights

``` r

reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
summarise(reweighted, mean_los = survey_mean(LOS))
#> # A tibble: 1 × 2
#>   mean_los mean_los_se
#>      <dbl>       <dbl>
#> 1     5.41       0.151
```

These factors illustrate how to apply multipliers. In a study, define
the target population and assess overlap and balance for the chosen
weighting method. The standard errors treat the supplied factors as
fixed. Use the original design for national discharge counts.
Multiplying by analysis weights changes what the totals estimate.
Annualization alone divides every design weight by the same number of
years.
