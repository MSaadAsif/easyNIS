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
  weight_var = "DISCWT",
  output = c("summary", "inventory"),
  sparse_n = 10L
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- codes:

  A named character vector or named list of character vectors. Each name
  is a `code_group`; each value contains prefixes. Names must be
  non-empty and unique.

- cohort:

  Optional tidy-evaluation logical expression defining the cohort. Rows
  where it evaluates to `NA` are excluded.

- by:

  Names of one or more existing columns defining periods, with no
  duplicates.

- type:

  Whether to match diagnosis (`"dx"`) or procedure (`"pr"`) slots.

- system:

  Code system of the slots: `"icd10"` (default) or `"icd9"`.

- weight_var:

  Name of the survey weight column, defaulting to `"DISCWT"`. Values in
  the selected cohort must be finite, non-missing numeric values.

- output:

  `"summary"` (default) for code-group frequencies or `"inventory"` for
  observed code matches by period.

- sparse_n:

  Largest unweighted count flagged `"sparse"` in the inventory. Defaults
  to 10, matching
  [`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md).
  Used only when `output = "inventory"`.

## Value

A collected tibble. For `output = "summary"`, the period columns from
`by`, `code_group`, `n_cohort_unweighted`, `n_unweighted`, `n_weighted`,
`pct_within_year`, and `yoy_pct_change`. The change is the relative
percent change in `pct_within_year` versus the previous observed period
in sorted order. It is `NA` for the first period, a period with a
missing value, when the previous period's percentage is zero, and in
every row when `by` names more than one column. For
`output = "inventory"`, the period columns, `code_group`, `code`,
`n_cohort_unweighted`, `n_unweighted`, `n_weighted`, and `status`.

## Details

`by` may name several columns, such as `c("YEAR", "DQTR")`. A period is
then one observed combination of their values, sorted by the columns in
the order given. A period with a missing value in any component is kept
as its own row, sorted after every complete period. Combinations that do
not occur in the data are not added. With several columns, no
unambiguous year comparison can be inferred, because adjacent
combinations may be quarters of one year or the boundary between two
other components. `yoy_pct_change` is therefore `NA` in every row;
compare `pct_within_year` across the periods you care about instead.

With `output = "inventory"`, the function instead lists the full codes
observed in the selected slots that start with each group's prefixes,
with unweighted and weighted discharge counts for every period. A
discharge is counted once per code, even when the code occupies several
slots. Each observed code is listed for every period, so a code that is
rare in some periods or missing from them is visible. `status` is
`"absent"` when the code has no matches in the period, `"sparse"` when
its unweighted count is at least one and at most `sparse_n`, and
`"observed"` otherwise. A group that matches no observed code is
returned with `code` missing and status `"absent"` in every period.
Counts are aggregated in the database for lazy inputs, so only
period-by-code counts are collected, however many codes a prefix
matches. The counts are exact, so apply your disclosure rules (see
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md))
before sharing them.

## See also

[Code transitions and
sensitivity](https://msaadasif.github.io/easyNIS/reference/articles/code-transitions.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

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

# Observed full codes by period, with absent and sparse periods flagged
nis_audit_code_transition(toy_data,
  codes = c(myectomy = "02UG", ablation = "0280"), output = "inventory")
#> # A tibble: 6 × 7
#>    YEAR code_group code    n_cohort_unweighted n_unweighted n_weighted status
#>   <int> <chr>      <chr>                 <int>        <int>      <dbl> <chr> 
#> 1  2018 myectomy   02UG0JZ                   2            2         10 sparse
#> 2  2019 myectomy   02UG0JZ                   2            1          5 sparse
#> 3  2020 myectomy   02UG0JZ                   2            0          0 absent
#> 4  2018 ablation   02803ZZ                   2            0          0 absent
#> 5  2019 ablation   02803ZZ                   2            1          5 sparse
#> 6  2020 ablation   02803ZZ                   2            2         10 sparse

# Periods defined by several columns
toy_data$DQTR <- c(1L, 2L, 1L, 2L, 1L, 2L)
nis_audit_code_transition(toy_data, c(myectomy = "02UG0JZ"),
  by = c("YEAR", "DQTR"))
#> # A tibble: 6 × 8
#>    YEAR  DQTR code_group n_cohort_unweighted n_unweighted n_weighted
#>   <int> <int> <chr>                    <int>        <int>      <dbl>
#> 1  2018     1 myectomy                     1            1          5
#> 2  2018     2 myectomy                     1            1          5
#> 3  2019     1 myectomy                     1            1          5
#> 4  2019     2 myectomy                     1            0          0
#> 5  2020     1 myectomy                     1            0          0
#> 6  2020     2 myectomy                     1            0          0
#> # ℹ 2 more variables: pct_within_year <dbl>, yoy_pct_change <dbl>
```
