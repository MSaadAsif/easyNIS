# Descriptives and regression

## Prepare one survey design

Declare the cohort in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
and keep the columns needed by the summary and model.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpyFtry0/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpyFtry0/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = AGE >= 18,
  keep = c(AGE, FEMALE, LOS, DIED, heart_failure),
  annualize = TRUE
)
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
  death_rate = srvyr::survey_mean(DIED)
)
#> # A tibble: 1 × 6
#>   discharges discharges_se mean_age mean_age_se death_rate death_rate_se
#>        <dbl>         <dbl>    <dbl>       <dbl>      <dbl>         <dbl>
#> 1       114.          2.83     59.6       0.597     0.0201       0.00829
```

All values come from invented rows and illustrate output shape only.

## Fit a survey-weighted model

[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fits
generalized linear models using the design.

``` r

fit <- survey::svyglm(
  DIED ~ heart_failure + AGE + FEMALE + factor(YEAR),
  design = design,
  family = quasibinomial()
)
summary(fit)
#> 
#> Call:
#> svyglm(formula = DIED ~ heart_failure + AGE + FEMALE + factor(YEAR), 
#>     design = design, family = quasibinomial())
#> 
#> Survey design:
#> Called via srvyr
#> 
#> Coefficients:
#>                     Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)        1.639e+00  1.906e+00   0.860  0.40442    
#> heart_failureTRUE -8.726e-01  1.715e+00  -0.509  0.61872    
#> AGE               -9.999e-02  2.814e-02  -3.553  0.00318 ** 
#> FEMALETRUE        -1.836e+01  7.455e-01 -24.626  6.3e-13 ***
#> factor(YEAR)2020  -1.246e-16  8.742e-01   0.000  1.00000    
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

## Tables with gtsummary

The examples below use gtsummary 2.6.1 or later.

Pass the result of
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
directly to
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).
The design supplies cohort discharges for unweighted sample sizes,
missing counts, and category counts. Hospital placeholders contribute to
the variance structure only. This table uses a survey t-test for mean
age and the design-adjusted chi-squared test for sex. The header shows
unweighted sample sizes, alongside weighted summaries in the table body.

``` r

gtsummary::tbl_svysummary(
  design,
  by = heart_failure,
  include = c(AGE, FEMALE),
  label = FEMALE ~ "Female",
  statistic = AGE ~ "{mean} ({mean.std.error})",
  missing_stat = "{N_miss_unweighted}"
) |>
  gtsummary::add_p(test = list(AGE ~ "svy.t.test", FEMALE ~ "svy.chisq.test")) |>
  gtsummary::add_overall() |>
  gtsummary::modify_header(gtsummary::all_stat_cols() ~ "**{level}** (unweighted N = {n_unweighted})")
```

| **Characteristic** | **TRUE** (unweighted N = 108)¹ | **Overall** (unweighted N = 192)¹ | **FALSE** (unweighted N = 84)¹ | **p-value**² |
|----|----|----|----|----|
| Age, years | 58 (1) | 60 (1) | 62 (1) | 0.035 |
| Female | 31 (50%) | 57 (50%) | 26 (50%) | \>0.9 |
| ¹ Mean (SE); n (%) |  |  |  |  |
| ² Design-based t-test; Pearson’s X^2: Rao & Scott adjustment |  |  |  |  |

Use `tbl_regression()` to format your fitted models and
`tbl_uvregression()` to fit and format a separate survey model for each
predictor. The logistic table reports odds ratios and the linear tables
report differences in mean length of stay.

``` r

gtsummary::tbl_regression(fit, exponentiate = TRUE)
```

[TABLE]

``` r


los_fit <- survey::svyglm(LOS ~ heart_failure + AGE + FEMALE, design = design)
gtsummary::tbl_regression(los_fit)
```

[TABLE]

``` r


gtsummary::tbl_uvregression(
  design,
  y = LOS,
  include = c(heart_failure, AGE, FEMALE),
  method = survey::svyglm
)
```

[TABLE]

For Parquet inputs, start with
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
and then use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
to build the in-memory cohort design used here. Passing a DuckDB-backed
survey `DBIsvydesign` directly to `tbl_svysummary()` fails with
gtsummary 2.6.1. Review unweighted cell counts and apply disclosure
rules before sharing.

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

## Whole-sample estimation on a laptop

Use
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
to estimate means, totals, or regression coefficients when discharge
rows would take too much memory. It uses a nested Taylor design with
hospital-year PSUs and year-specific strata. DuckDB scans the Parquet
data and sends weighted PSU sums to R. Use
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
on the design to estimate a domain. `subset(whole, AGE >= 65)` is the
survey-style alternative. Filtering the query before constructing the
design changes the sample.

``` r

whole <- nis_survey(nis)
older <- dplyr::filter(whole, AGE >= 65)
survey::svyby(~LOS, ~YEAR, older, survey::svymean)
#>      YEAR      LOS        se
#> 2019 2019 4.577143 0.4142243
#> 2020 2020 4.577143 0.4142243
fit <- survey::svyglm(LOS ~ AGE + factor(YEAR), older)
broom::tidy(fit, conf.int = TRUE)
#> # A tibble: 3 × 7
#>   term             estimate std.error statistic  p.value conf.low conf.high
#>   <chr>               <dbl>     <dbl>     <dbl>    <dbl>    <dbl>     <dbl>
#> 1 (Intercept)        15.3      3.08        4.96 0.000143    8.73    21.8   
#> 2 AGE                -0.138    0.0373     -3.70 0.00196    -0.217   -0.0588
#> 3 factor(YEAR)2020    0        0.586       0    1          -1.24     1.24
```

For a
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
fit,
[`gtsummary::tbl_regression()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_regression.html)
reports the unweighted number of complete discharges as N. For a
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
fit, N comes from the analysis weights.

Use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
for row-level cohort analysis, including quantiles, chi-square tests,
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html),
and IPTW. Use the disclosure workflow before sharing results.
