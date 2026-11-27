# Trends

## Choose comparable years

The 2012 NIS redesign changed the sampling unit from hospitals to
discharges. Use `DISCWT` from 2012 onward. For a study that crosses the
redesign, HCUP specifies replacement `TRENDWT` for 1993–2011 and
`DISCWT` from 2012 onward. The easyNIS trend workflow starts in 2012.
The survey design scopes both `HOSP_NIS` and `NIS_STRATUM` by year.
Hospital numbers can recur across releases and cannot identify the same
hospital over time. [Introduction to the
NIS](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2021.jsp),
[2012 redesign, Methods Series
2014-04](https://hcup-us.ahrq.gov/reports/methods/2014-04.pdf), [NIS
trend weights](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp).

2015 Q1–Q3 use ICD-9-CM and Q4 uses ICD-10-CM/PCS. For a diagnosis- or
procedure-based cohort or outcome, start with complete years within one
coding era (2012–2014 or 2016 onward). Run separate analyses to describe
both eras. If a study must include the transition, examine quarterly
frequencies for discontinuities and report how the definition and
coverage change. Read HCUP’s recommendations before combining quarters
or fitting a model across the break. Set
`coding = "verified_comparable"` only when the definition is
coding-independent, such as total adult discharges based on age, or a
quarterly audit found no coding discontinuity between Q3 and Q4. Report
the coding change and the basis for comparability. The function rejects
a 2015 cohort confined to either side of the transition. [HCUP
recommendations for reporting
trends](https://hcup-us.ahrq.gov/datainnovations/HCUP_RecomForReportingTrends_070517.pdf).

Check the Known Data Issues section for corrections to the releases you
use, including the notices for 2019–2020. Check the annual introductions
for changes to variable availability and definitions. [NIS Database
Documentation](https://hcup-us.ahrq.gov/db/nation/nis/nisdbdocumentation.jsp).

## Estimate a total for each year

Open the complete annual samples and pass the cohort as a logical
expression.
[`nis_annual_totals()`](https://msaadasif.github.io/easyNIS/reference/nis_annual_totals.md)
uses each year’s original discharge weights. It checks whether all four
quarters have valid design records in each input year. Verify sample
completeness separately. Missing estimates and zero support counts
identify years with no valid cohort discharges in the design.

``` r

nis <- nis_open(nis_example(years = 2018:2020)) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_outcomes()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp99UL52/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp99UL52/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

annual <- nis_annual_totals(nis, heart_failure)
#> Cohort: 162 discharges; weighted N 187.2; 27 hospitals across 3 years.
nis_suppress(
  annual,
  count_col = "n",
  hospital_col = "hospitals",
  weighted_cols = c("discharges", "discharges_se")
)
#> # A tibble: 3 × 5
#>    YEAR discharges discharges_se    n     hospitals
#>   <int> <chr>      <chr>            <chr> <chr>    
#> 1  2018 62.4       12.2670289801565 54    9        
#> 2  2019 62.4       12.2670289801565 54    9        
#> 3  2020 62.4       12.2670289801565 54    9
```

Report the calendar years, cohort definition, weight, and design used to
compute standard errors. Apply [disclosure
rules](https://msaadasif.github.io/easyNIS/articles/disclosure.md)
before sharing estimates, plots, or tests. The examples use invented
discharges.

## Estimate a rate with a population denominator

A population rate needs an external population aligned to the
numerator’s calendar year, geography, and age range. The following
denominators are invented national all-age populations. This rate counts
hospitalizations involving heart failure per 100,000 residents. A
resident can contribute multiple discharges.

``` r

population <- data.frame(YEAR = 2018:2020, residents = c(3e8, 3.01e8, 3.02e8))
stopifnot(
  !anyDuplicated(population$YEAR),
  identical(sort(population$YEAR), seq.int(min(annual$YEAR), max(annual$YEAR))),
  identical(annual$YEAR, sort(population$YEAR)),
  all(is.finite(population$residents) & population$residents > 0)
)
rates <- annual |>
  dplyr::left_join(population, by = "YEAR", relationship = "one-to-one") |>
  dplyr::mutate(
    rate = 1e5 * discharges / residents,
    rate_se = 1e5 * discharges_se / residents
  )
rates
#> # A tibble: 3 × 8
#>    YEAR discharges discharges_se     n hospitals residents   rate rate_se
#>   <int>      <dbl>         <dbl> <int>     <int>     <dbl>  <dbl>   <dbl>
#> 1  2018       62.4          12.3    54         9 300000000 0.0208 0.00409
#> 2  2019       62.4          12.3    54         9 301000000 0.0207 0.00408
#> 3  2020       62.4          12.3    54         9 302000000 0.0207 0.00406
```

The rate and its standard error use the same scale factor. This
calculation treats the external population as fixed. Validate coverage
before joining so a missing year cannot silently produce a missing
denominator. For release, apply suppression to the rate and its standard
error using the numerator’s support counts. Review any other tables that
share the numerator.

## Estimate a discharge proportion and a mean by period

For the proportion of eligible discharges ending in in-hospital death,
take the survey mean of the logical death indicator. The second mean
estimates length of stay in days. Each measure uses its own nonmissing
denominator. Build the design on the complete sample, restrict the
domain, then group.

``` r

period_design <- nis_design(
  nis, heart_failure, keep = c(DQTR, in_hospital_death, los_days)
)
#> Cohort: 162 discharges; weighted N 187.2; 27 hospitals across 3 years.
period_design |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(
    proportion_died = srvyr::survey_mean(in_hospital_death, na.rm = TRUE),
    mean_los = srvyr::survey_mean(los_days, na.rm = TRUE),
    .groups = "drop"
  )
#> # A tibble: 3 × 5
#>    YEAR proportion_died proportion_died_se mean_los mean_los_se
#>   <int>           <dbl>              <dbl>    <dbl>       <dbl>
#> 1  2018          0.0176             0.0175     5.66       0.324
#> 2  2019          0.0176             0.0175     5.66       0.324
#> 3  2020          0.0176             0.0175     5.66       0.324
period_design |>
  dplyr::group_by(YEAR, DQTR) |>
  dplyr::summarise(
    proportion_died = srvyr::survey_mean(in_hospital_death, na.rm = TRUE),
    mean_los = srvyr::survey_mean(los_days, na.rm = TRUE),
    .groups = "drop"
  )
#> # A tibble: 12 × 6
#>     YEAR DQTR  proportion_died proportion_died_se mean_los mean_los_se
#>    <int> <fct>           <dbl>              <dbl>    <dbl>       <dbl>
#>  1  2018 Q1             0                  0          5.62       0.692
#>  2  2018 Q2             0                  0          5.55       1.25 
#>  3  2018 Q3             0                  0          5.12       0.711
#>  4  2018 Q4             0.0529             0.0524     6.03       0.502
#>  5  2019 Q1             0                  0          5.62       0.692
#>  6  2019 Q2             0                  0          5.55       1.25 
#>  7  2019 Q3             0                  0          5.12       0.711
#>  8  2019 Q4             0.0529             0.0524     6.03       0.502
#>  9  2020 Q1             0                  0          5.62       0.692
#> 10  2020 Q2             0                  0          5.55       1.25 
#> 11  2020 Q3             0                  0          5.12       0.711
#> 12  2020 Q4             0.0529             0.0524     6.03       0.502
```

These are shares of discharges within each period. Check support for
each reported measure, including its nonmissing denominator and the
event and nonevent counts for the proportion. Empty domains may be
absent from grouped results.

### Keep the two 2015 coding periods separate

For a code-defined cohort in 2015, define each quarter’s eligibility
using its coding system. The example uses principal heart failure codes
and keeps all four quarters in the sample used to build the design.
Compute separate estimates for Q1–Q3 and Q4, with unscaled weights.

``` r

transition <- nis_open(nis_example(2015)) |>
  # Replace the fixture's placeholder code with an ICD-9-CM example.
  dplyr::mutate(DX1 = dplyr::if_else(DX1 == "12345", "4280", DX1)) |>
  nis_flag_dx(hf9 = "428", system = "icd9", position = "principal") |>
  nis_flag_dx(hf10 = "I50", system = "icd10", position = "principal") |>
  dplyr::mutate(period = dplyr::if_else(DQTR == 4L, "Q4", "Q1-Q3"))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp99UL52/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Experimental: years before 2016 store ICD-9-CM codes in DX1, PR1, ... slots.
#> ℹ Flag them with `system = "icd9"`; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4)
#>   slots.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp99UL52/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

split <- nis_design(
  transition,
  cohort = (DQTR <= 3L & hf9) | (DQTR == 4L & hf10),
  keep = period,
  annualize = FALSE
) |>
  dplyr::group_by(period) |>
  dplyr::summarise(discharges = srvyr::survey_total())
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
split
#> # A tibble: 2 × 3
#>   period discharges discharges_se
#>   <chr>       <dbl>         <dbl>
#> 1 Q1-Q3        41.6          8.18
#> 2 Q4           20.8          4.09
```

The totals describe periods of different lengths. Document each code set
and its coverage before comparing estimates across the transition.

## Estimate an average annual total

If the target is the **average annual number** of cohort discharges over
the included complete years, pool with `annualize = TRUE`. This divides
the weights by the number of included years, scaling both the pooled
total and its standard error. A year without cohort discharges still
contributes to the divisor. Use `annualize = FALSE` for the cumulative
total across those years. A pooled weighted mean or proportion describes
the pooled discharge population. Dividing every weight by the same
number leaves it unchanged. Report the denominator in proportions, for
example all eligible discharges for a share of NIS discharges.

``` r

pooled <- nis_design(nis, heart_failure, keep = YEAR, annualize = TRUE)
#> Cohort: 162 discharges; weighted N 62.4; 27 hospitals across 3 years.
srvyr::summarise(pooled, annual_discharges = srvyr::survey_total())
#> # A tibble: 1 × 2
#>   annual_discharges annual_discharges_se
#>               <dbl>                <dbl>
#> 1              62.4                 7.08
```

## Test for linear change in an outcome

Define the outcome and the time scale before fitting a trend. For
example, use survey-weighted regression to estimate the change in mean
length of stay per calendar year among heart failure discharges. Center
calendar year to make the intercept the fitted mean for the first year.
Calendar-time spacing is preserved when included years have gaps.

``` r

design <- nis_design(nis, heart_failure, keep = LOS) |>
  dplyr::mutate(elapsed = YEAR - 2018L)
#> Cohort: 162 discharges; weighted N 187.2; 27 hospitals across 3 years.

fit <- survey::svyglm(LOS ~ elapsed, design = design)
summary(fit)$coefficients["elapsed", ]
#>     Estimate   Std. Error      t value     Pr(>|t|) 
#> 2.646794e-16 2.289912e-01 1.155850e-15 1.000000e+00
```

The coefficient and its design-based uncertainty describe change in mean
length of stay, measured in days per year. Choose a model and
denominator that match the outcome. For a binary outcome, a
quasibinomial survey model with numeric year estimates linear change on
the log-odds scale. For year-specific comparisons, specify year as a
factor. Changes in case mix, coding, and practice can all affect the
slope. A discharge-level outcome model answers a different question from
a time-series model for annual national volumes. [HCUP trend methods,
Methods Series
2006-05](https://hcup-us.ahrq.gov/reports/methods/2006_05_NISTrendsReport_1988-2004A.pdf),
[Variance estimation, Methods Series
2015-09](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp).

Published NIS studies illustrate how to report the choice of estimand
and methods. Alkhouli and colleagues specified the calendar periods and
distinguished trend tests for categorical and continuous outcomes. The
study of surgical treatment for pseudotumor cerebri reported annual
procedure counts and described its survey regression and coding-era
adjustment. [Alkhouli et al., JAMA Network Open
(2020)](https://doi.org/10.1001/jamanetworkopen.2019.21326), [JAMA
Ophthalmology study
(2020)](https://jamanetwork.com/journals/jamaophthalmology/fullarticle/2774167).
