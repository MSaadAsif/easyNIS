# Descriptives and regression

## Prepare one survey design

Declare the cohort in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
and keep the columns needed by the summary and model.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50") |>
  dplyr::mutate(death = as.integer(DIED))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpw716lX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpw716lX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpw716lX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = AGE >= 18,
  keep = c(AGE, FEMALE, LOS, DIED, death, heart_failure),
  annualize = TRUE
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 192 discharges; weighted N 114.4; 24 hospitals across 2 years.
```

The design contains adult cohort rows. For hospital-years with no cohort
rows,
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
adds placeholder rows so those hospital-years remain represented in the
design’s variance structure. This placeholder method is experimental;
review the design construction and its suitability for your analysis.

## Estimate weighted summaries

`srvyr` adds tidy verbs to survey designs. The total below is an
annualized weighted discharge estimate; the mean and its standard error
use the survey design.

``` r

srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_age = srvyr::survey_mean(AGE),
  death_rate = srvyr::survey_mean(death)
)
#> # A tibble: 1 × 6
#>   discharges discharges_se mean_age mean_age_se death_rate death_rate_se
#>        <dbl>         <dbl>    <dbl>       <dbl>      <dbl>         <dbl>
#> 1       114.          2.83     59.6       0.597     0.0201       0.00829
```

All values come from invented rows and illustrate output shape only.

## Build a Table 1

[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
formats weighted descriptive statistics. These optional packages are
needed for this section.

``` r

table_one <- gtsummary::tbl_svysummary(
  design,
  by = heart_failure,
  include = c(AGE, FEMALE, LOS, DIED)
) |>
  gtsummary::add_overall()
table_one
```

[TABLE]

The columns compare the flag groups with an overall column. Inspect the
unweighted cell counts before sharing; the table is not automatically
disclosure-cleared.

## Fit a survey-weighted model

[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fits
generalized linear models using the design.

``` r

fit <- survey::svyglm(
  death ~ heart_failure + AGE + FEMALE + factor(YEAR),
  design = design,
  family = quasibinomial()
)
summary(fit)
#> 
#> Call:
#> svyglm(formula = death ~ heart_failure + AGE + FEMALE + factor(YEAR), 
#>     design = design, family = quasibinomial())
#> 
#> Survey design:
#> Called via srvyr
#> 
#> Coefficients:
#>                    Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)       1.639e+00  1.906e+00   0.860  0.40442    
#> heart_failureYes -8.726e-01  1.715e+00  -0.509  0.61872    
#> AGE              -9.999e-02  2.814e-02  -3.553  0.00318 ** 
#> FEMALEFemale     -1.836e+01  7.455e-01 -24.626  6.3e-13 ***
#> factor(YEAR)2020  8.200e-17  8.742e-01   0.000  1.00000    
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> (Dispersion parameter for quasibinomial family taken to be 0.1660637)
#> 
#> Number of Fisher Scoring iterations: 20
```

Coefficients describe model associations under the survey design; they
do not establish causality. The synthetic data are too small and
artificial for substantive conclusions.

## Common pitfalls

> **Common pitfalls**
>
> - Use `survey`/`srvyr` methods on the survey design, not ordinary
>   row-level summaries when reporting design-based uncertainty.
> - A weighted estimate does not validate the cohort definition, model,
>   or causal interpretation.
> - Apply disclosure review separately; weighted summaries alone do not
>   show whether counts are safe to report.

See [Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md),
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
and [Disclosure and
suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.md).
