# Survey design and weighting

## Build the cohort design

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
validates `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, and `DISCWT`, then
constructs a survey design before applying the declared domain. Existing
dplyr groups (including rowwise grouping) are removed first, for both
data frames and lazy DuckDB queries. Aggregate cohort expressions such
as `LOS > mean(LOS)` use the full input rather than each input group. To
use a group-specific threshold, compute an explicit cohort indicator
upstream and pass that column to `cohort`. Group the returned survey
design when you need grouped survey summaries.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzdB3Ke/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzdB3Ke/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 18,
  keep = c(AGE, LOS),
  annualize = TRUE
)
#> Preparing the cohort survey design.
srvyr::summarise(design, total = srvyr::survey_total(),
                 mean_los = srvyr::survey_mean(LOS))
#> # A tibble: 1 × 4
#>   total total_se mean_los mean_los_se
#>   <dbl>    <dbl>    <dbl>       <dbl>
#> 1  62.4     8.67     5.66       0.229
```

The output contains a weighted fixture total and mean LOS with
design-based standard errors. Hospital placeholders account for
hospital-years with no cohort discharges in the variance calculation.
The returned design exposes only cohort discharges to summaries. This
placeholder strategy is experimental.

For lazy inputs, DuckDB computes hospital-year strata, invalid-field
counts, and annualization coverage in one sample scan. The separate
cohort scan collects the selected columns needed to build the survey
design in R.

## Analyze a domain within the cohort

The object returned by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
is already an srvyr survey design. Use
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
on that object to define an analytic domain. Like
[`subset()`](https://rdrr.io/r/base/subset.html) on a survey design, it
uses the original sampling structure for variance. Hospitals with no
domain discharges contribute zero, including when an entire stratum
falls outside the domain.

On the design returned by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`filter()`](https://rdrr.io/r/stats/filter.html) also removes
out-of-domain records from the stored analysis data. The survey design
retains the original sampled hospital counts for variance estimation, so
there is no separate compaction step. If you no longer need the wider
design, assign the filtered result back to the same variable.

``` r

design |>
  dplyr::filter(AGE >= 65) |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(
    mean_los = srvyr::survey_mean(LOS),
    discharges = srvyr::unweighted(dplyr::n())
  )
#> # A tibble: 2 × 4
#>    YEAR mean_los mean_los_se discharges
#>   <int>    <dbl>       <dbl>      <int>
#> 1  2019     5.11       0.606         22
#> 2  2020     5.11       0.606         22
```

`discharges` counts only observed domain discharges. The filtered design
can also be passed directly to survey functions and to
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).

Filtering the lazy input before
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
restricts the records available to construct the design and can remove
entire hospitals or strata. To define a cohort within the available
sample, pass the inclusion criteria to `cohort`. To narrow an existing
design to a subpopulation, filter the returned design.

## Choose a pooling convention

Without annualization, pooled-year weights represent the combined
included period. `annualize = TRUE` divides by the number of valid
years; partial years count as a year. When quarter fields are present
the function warns about incomplete year coverage and a 2015 cohort
restricted to one coding era. Exclude partial years or choose a
documented alternative if this convention does not fit the estimand.

## Run a weighted sensitivity analysis

Use the original survey design for national totals. The example below
compares the original mean LOS difference with one weighted to balance
the observed age distribution between groups. It uses invented data and
targets the age distribution of the pooled adult discharge population.
The propensity model uses age as its only predictor.

``` r

original <- nis_design(nis, AGE >= 18, keep = c(AGE, LOS, heart_failure))
#> Preparing the cohort survey design.
propensity <- survey::svyglm(
  heart_failure ~ AGE, design = original, family = quasibinomial()
)
p <- stats::predict(propensity, newdata = original$variables, type = "response")
stopifnot(all(is.finite(p) & p > 0 & p < 1))

weighted <- nis_reweight(original, ifelse(heart_failure, 1 / p, 1 / (1 - p)))
age_by_group <- function(design) {
  survey::svyby(~AGE, ~heart_failure, design, survey::svymean)
}
los_contrast <- function(design) {
  fit <- survey::svyglm(LOS ~ heart_failure, design)
  summary(fit)$coefficients["heart_failureTRUE", c("Estimate", "Std. Error")]
}

age_by_group(original)
#>       heart_failure      AGE        se
#> FALSE         FALSE 62.04231 1.2732597
#> TRUE           TRUE 57.55769 0.9866784
age_by_group(weighted)
#>       heart_failure      AGE        se
#> FALSE         FALSE 59.63008 1.4907428
#> TRUE           TRUE 59.63404 0.9660242
rbind(original = los_contrast(original), reweighted = los_contrast(weighted))
#>             Estimate Std. Error
#> original   0.2826923  0.4126637
#> reweighted 0.1555133  0.4113503
srvyr::summarise(original, national_discharges = srvyr::survey_total())
#> # A tibble: 1 × 2
#>   national_discharges national_discharges_se
#>                 <dbl>                  <dbl>
#> 1                229.                   5.66
```

[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
is experimental. It multiplies the survey weights by the supplied
factors, in the order of the design rows. The weighted mean contrast and
its standard error use that transformed design. This variance treats the
supplied factors as fixed. Report the propensity specification, weight
range, any trimming or exclusions, and balance in the variables used to
justify the sensitivity analysis. The age means illustrate one balance
check. The example uses all weights without trimming. Causal
interpretation would require a justified exposure definition, target
population, and assumptions about confounding and overlap.

## Why design-based standard errors matter

NIS uses hospital clusters, strata, and discharge weights. Ordinary
means and standard errors treat rows as if they came from a simple
random sample and do not reflect that structure. Use `srvyr` or `survey`
methods on the returned design for point estimates and uncertainty. A
survey standard error is an estimate of sampling variability under the
supplied design, not a guarantee that all sources of bias have been
addressed.

## Inspect exclusions

Rows with missing, non-finite, or non-positive design fields are
excluded before the cohort is applied. Inspect the aggregate audit
attribute and report the exclusions with the analysis.

``` r

attr(design, "nis_excluded")
#> $total
#> [1] 0
#> 
#> $by_field
#>        YEAR    HOSP_NIS NIS_STRATUM      DISCWT 
#>           0           0           0           0 
#> 
#> $by_year
#> # A tibble: 0 × 2
#> # ℹ 2 variables: YEAR <int>, n <dbl>
```

This list gives counts by field and year, not record-level information.

## Common pitfalls

> **Common pitfalls**
>
> - Treating annualized weights as a correction for arbitrary
>   partial-year coverage.
> - Using non-survey summaries for estimates or uncertainty.
> - Treating reweighting or placeholder-row variance methods as
>   established methods; both are experimental.

See
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md),
and [Data notes by
year](https://msaadasif.github.io/easyNIS/articles/year-notes.md).
