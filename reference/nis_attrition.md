# Summarize sequential cohort attrition

Applies logical criteria cumulatively and reports remaining and dropped
discharge counts at each step. Criteria are evaluated in order; `NA`
values are treated as excluded, matching
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html).
The summary is aggregated lazily for Arrow queries and returned as a
collected tibble. Missing weights contribute zero to weighted totals.

## Usage

``` r
nis_attrition(.data, ..., by_year = FALSE, weight_var = "DISCWT")
```

## Arguments

- .data:

  A data frame or lazy Arrow query.

- ...:

  Named logical expressions applied cumulatively. Unnamed expressions
  use their deparsed text as the criterion label.

- by_year:

  If `TRUE`, calculate each step within `YEAR`.

- weight_var:

  Name of the discharge weight column. Defaults to `"DISCWT"`.

## Value

A tibble with one initial row (`step = 0`) and one row per criterion.
When `by_year = TRUE`, `YEAR` is the first column.

## Examples

``` r
toy_nis <- dplyr::tibble(
  AGE = c(16, 45, 60, 72, 55),
  ELECTIVE = c(1, 1, 0, 1, 1),
  DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
  YEAR = rep(2020L, 5)
)
nis_attrition(toy_nis, adult = AGE >= 18, elective = ELECTIVE == 1)
#> # A tibble: 3 × 7
#>    step criterion      n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                 <int>                <int>      <dbl>
#> 1     0 All discharges            5                    0       25.1
#> 2     1 adult                     4                    1       20.1
#> 3     2 elective                  3                    1       15.3
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
```
