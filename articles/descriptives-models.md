# Descriptives and regression

## Prepare one survey design

Declare the cohort in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
and keep the columns needed by the summary and model.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_outcomes()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpVgMdPf/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpVgMdPf/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = AGE >= 18,
  keep = c(AGE, FEMALE, LOS, in_hospital_death, heart_failure),
  annualize = TRUE
)
#> Preparing the cohort survey design.
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
  death_proportion = srvyr::survey_mean(in_hospital_death, na.rm = TRUE)
)
#> # A tibble: 1 × 6
#>   discharges discharges_se mean_age mean_age_se death_proportion
#>        <dbl>         <dbl>    <dbl>       <dbl>            <dbl>
#> 1       114.          2.83     59.6       0.597           0.0201
#> # ℹ 1 more variable: death_proportion_se <dbl>
```

All values come from invented rows and illustrate output shape only.

## Fit a survey-weighted model

[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fits
generalized linear models using the design.

``` r

fit <- survey::svyglm(
  in_hospital_death ~ heart_failure + AGE + FEMALE + factor(YEAR),
  design = design,
  family = quasibinomial()
)
term <- "heart_failureTRUE"
interval <- exp(confint(fit, parm = term))
data.frame(
  model_n = nrow(stats::model.frame(fit)),
  odds_ratio = exp(coef(fit)[[term]]),
  lower = interval[1L],
  upper = interval[2L]
)
#>   model_n odds_ratio      lower   upper
#> 1     192  0.4178614 0.01056816 16.5221
```

The odds ratio compares adult discharges with and without a recorded
heart failure diagnosis at the same age, sex, and year in this model.
The model frame counts discharges with complete values for this formula.
The interval uses design-based standard errors and the model’s residual
degrees of freedom. The results illustrate an adjusted association in
invented data.

### Contrast two mean lengths of stay

With a single binary predictor, the Gaussian survey model coefficient is
the difference in weighted mean LOS, in days. It subtracts the mean
among discharges without a heart failure code from the mean among
discharges with one. The fit gives the design-based standard error of
the difference.

``` r

los_difference <- survey::svyglm(LOS ~ heart_failure, design = design)
nrow(stats::model.frame(los_difference))
#> [1] 192
summary(los_difference)$coefficients[term, ]
#>   Estimate Std. Error    t value   Pr(>|t|) 
#>  0.2826923  0.4126637  0.6850428  0.5025514
confint(los_difference, parm = term)
#>                       2.5 %   97.5 %
#> heart_failureTRUE -0.587952 1.153337
```

Report the complete-case discharge count for each model. See [Survey
design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.html#run-a-weighted-sensitivity-analysis)
for an example that changes the target of the mean contrast through
reweighting.

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

The default continuous summary uses a weighted median and quartiles. On
a large cohort, computing those quantiles for each group can dominate
table runtime. Use `include` to select the variables the table needs.
When a weighted mean answers the scientific question, request one
explicitly with `statistic = AGE ~ "{mean} ({mean.std.error})"`.

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
