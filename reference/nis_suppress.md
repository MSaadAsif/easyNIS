# Suppress small unweighted cells in a survey summary

Replaces displayed statistics when their corresponding unweighted count
is at or below `threshold`. Counts come from the `cards` computed by
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).
Continuous2 statistic rows use the non-missing count for their
corresponding output column. If that count is absent, ambiguous, or
non-finite for a displayed statistic, the function errors; blank
statistic cells do not require a count. When a by-group cell is masked,
the overall cell (`stat_0`) in the same row is marked `Masked`, unless
its own count is at or below the threshold. Other derivable cells still
need analyst review before sharing.

## Usage

``` r
nis_suppress(x, threshold = 10)
```

## Arguments

- x:

  A
  [`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
  result, optionally with `add_p()` or `add_overall()`.

- threshold:

  Maximum unweighted cell count to suppress.

## Value

The table with primary and secondary masks and a footnote describing
them.

## Examples

``` r
if (rlang::is_installed(c("gtsummary", "cardx", "survey"))) {
  nis <- nis_open(nis_example(years = 2019:2020)) |>
    nis_flag_dx(heart_failure = "I50")
  design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
  table <- gtsummary::tbl_svysummary(
    design,
    by = RACE,
    include = c(AGE, FEMALE)
  )
  nis_suppress(table, threshold = 10)
}
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.


  

Characteristic
```
