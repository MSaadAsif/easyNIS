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
#> ℹ /tmp/RtmpDd0kSH/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpDd0kSH/duckdb
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

### Choose continuous summaries for large tables

By default,
[`tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
computes a survey-weighted median and quartiles for each continuous
variable in each group. On a large design, those quantiles and the
repeated survey calculations for each group can take much longer than
the disclosure pass.

If the analysis calls for a mean and its standard error, request them
through `statistic` and apply the same disclosure checks.

``` r

tbl_svysummary(
  table_design,
  by = heart_failure,
  include = c(AGE, LOS, DIED),
  statistic = list(all_continuous() ~ "{mean} ({mean.std.error})")
) |>
  nis_suppress()
```

[TABLE]

The standard error describes uncertainty in the estimated mean. Keep the
default summaries when you need the median and quartiles to describe the
distribution. See the [gtsummary statistic
reference](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
for other supported summaries.

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

## Report weighted event rates

To report in-hospital mortality among adults under age 65, filter the
survey design so hospitals with no discharges in the domain still
contribute to variance estimation. Here the rates and the model use the
same complete cases. Include any additional model covariates in the
missing-value checks if you want both analyses to use the same
discharges.

``` r

mortality_design <- design |>
  filter(AGE < 65, !is.na(DIED), !is.na(heart_failure))
design_df <- survey::degf(mortality_design)

rates <- mortality_design |>
  group_by(heart_failure) |>
  summarise(
    events_sampled = unweighted(sum(DIED)),
    discharges_sampled = unweighted(n()),
    events_weighted = survey_total(DIED, vartype = NULL),
    discharges_weighted = survey_total(vartype = NULL),
    rate = survey_mean(DIED, vartype = c("se", "ci"), df = design_df)
  )
```

The rate is the weighted share of discharges with an in-hospital death.
The sampled columns count observed deaths and discharges. The weighted
columns estimate their totals over the years in the design. The rate,
standard error, and 95% confidence limits are on the 0–1 scale.

Before displaying the rates or their counts, check support for both
deaths and discharges without a death. An absent outcome level has zero
support. Mask the rate, its uncertainty, and all counts together when
either outcome level is protected.

``` r

support <- nis_cell_counts(mortality_design, by = c(heart_failure, DIED)) |>
  group_by(heart_failure) |>
  summarise(
    min_sampled = if (n() == 2L) min(n) else 0L,
    min_hospitals = if (n() == 2L) min(hospitals) else 0L,
    .groups = "drop"
  )

rates_for_review <- rates |>
  left_join(support, by = "heart_failure") |>
  nis_suppress(
    count_col = min_sampled,
    hospital_col = min_hospitals,
    weighted_cols = c(events_sampled, discharges_sampled, events_weighted,
                      discharges_weighted, rate, rate_se, rate_low, rate_upp)
  ) |>
  select(-min_sampled, -min_hospitals)
rates_for_review
#> # A tibble: 2 × 9
#>   heart_failure events_sampled discharges_sampled events_weighted
#>   <lgl>         <chr>          <chr>              <chr>          
#> 1 FALSE         ≤10            ≤10                ≤10            
#> 2 TRUE          ≤10            ≤10                ≤10            
#> # ℹ 5 more variables: discharges_weighted <chr>, rate <chr>, rate_se <chr>,
#> #   rate_low <chr>, rate_upp <chr>
```

Complementary suppression is on by default: if one exposure group is
masked, a second group is masked too, so the masked group can’t be
recovered from the cohort total reported elsewhere. Still review
overlapping tables, totals, and contrasts for deductions from masked
cells before sharing. See [disclosure
review](https://msaadasif.github.io/easyNIS/articles/disclosure.md).

## Estimate adjusted probabilities and a reference difference

[`survey::svypredmeans()`](https://rdrr.io/pkg/survey/man/svypredmeans.html)
takes an adjustment model whose formula omits the exposure. It adds the
exposure as a main effect, then averages the predicted probabilities at
each exposure level over the same weighted age distribution in the
analytic domain.
[`survey::svycontrast()`](https://rdrr.io/pkg/survey/man/svycontrast.html)
uses the covariance of the margins to estimate the difference from the
no-heart-failure reference.

``` r

adjustment <- survey::svyglm(
  DIED ~ AGE,
  design = mortality_design,
  family = quasibinomial()
)
margins <- survey::svypredmeans(
  adjustment, ~heart_failure, predictat = c(FALSE, TRUE)
)
estimates <- survey::svycontrast(
  margins,
  list(
    "No heart failure" = c("FALSE" = 1),
    "Heart failure" = c("TRUE" = 1),
    "Difference vs. no heart failure" = c("FALSE" = -1, "TRUE" = 1)
  )
)
limits <- confint(estimates, df = design_df)
adjusted <- tibble::tibble(
  term = names(coef(estimates)),
  estimate = as.numeric(coef(estimates)),
  std.error = as.numeric(survey::SE(estimates)),
  conf.low = limits[, 1],
  conf.high = limits[, 2]
)
adjusted
#> # A tibble: 3 × 5
#>   term                            estimate std.error conf.low conf.high
#>   <chr>                              <dbl>     <dbl>    <dbl>     <dbl>
#> 1 No heart failure                  0.0515    0.0284 -0.00814    0.111 
#> 2 Heart failure                     0.0285    0.0210 -0.0157     0.0727
#> 3 Difference vs. no heart failure  -0.0230    0.0415 -0.110      0.0642
```

Multiply the difference by 100 to report percentage points. The adjusted
probabilities and contrast above are for invented data. Before reporting
results from a study, check the outcome and exposure cells in the fitted
sample and assess what the predictions and contrast could reveal
together with the other outputs.

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
