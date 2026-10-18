# Audit code-group frequencies across periods

Counts discharges matching each named code-prefix group by period. A
discharge is counted once per group, even when multiple slots match.
Prefix matching follows
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
or
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
according to `type`. The complete grid of observed periods and code
groups is returned, with zero counts where a group has no matches.
Counts apply only to the selected code system; zero does not mean the
code is absent under another system. Audits across the 2015 ICD
transition need separate calls for each system. The change compares with
the previous observed period in sorted order.

## Usage

``` r
nis_audit_code_transition(
  .data,
  codes,
  cohort = NULL,
  by = "YEAR",
  type = c("pr", "dx"),
  system = c("icd10", "icd9"),
  weight_var = "DISCWT"
)
```

## Arguments

- .data:

  A data frame or lazy Arrow query.

- codes:

  A named character vector or named list of character vectors. Each name
  is a `code_group`; each value contains prefixes. Names must be
  non-empty and unique.

- cohort:

  Optional tidy-evaluation logical expression defining the cohort. Rows
  where it evaluates to `NA` are excluded.

- by:

  Name of the column defining periods. Must be one existing column.

- type:

  Whether to match diagnosis (`"dx"`) or procedure (`"pr"`) slots.

- system:

  Code system of the slots: `"icd10"` (default) or `"icd9"`.

- weight_var:

  Name of the survey weight column, defaulting to `"DISCWT"`.

## Value

A collected tibble with the period column, `code_group`,
`n_cohort_unweighted`, `n_unweighted`, `n_weighted`, `pct_within_year`,
and `yoy_pct_change`. The change is the relative percent change in
`pct_within_year` versus the previous observed period in sorted order.
It is `NA` for the first period, a missing period, or when the previous
period's percentage is zero.

## Examples

``` r
toy_data <- dplyr::tibble(
  YEAR = c(2018L, 2018L, 2019L, 2019L, 2020L, 2020L),
  I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02803ZZ", "02803ZZ", "02803ZZ"),
  DISCWT = rep(5, 6)
)
nis_audit_code_transition(toy_data,
  codes = c(myectomy = "02UG0JZ", ablation = "02803ZZ"))
#> # A tibble: 6 × 7
#>    YEAR code_group n_cohort_unweighted n_unweighted n_weighted pct_within_year
#>   <int> <chr>                    <int>        <int>      <dbl>           <dbl>
#> 1  2018 myectomy                     2            2         10             100
#> 2  2019 myectomy                     2            1          5              50
#> 3  2020 myectomy                     2            0          0               0
#> 4  2018 ablation                     2            0          0               0
#> 5  2019 ablation                     2            1          5              50
#> 6  2020 ablation                     2            2         10             100
#> # ℹ 1 more variable: yoy_pct_change <dbl>
```
