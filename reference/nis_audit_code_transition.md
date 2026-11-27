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
transition need separate calls for each system when supplying prefixes
directly. The change compares with the previous observed period in
sorted order.

## Usage

``` r
nis_audit_code_transition(
  .data,
  codes,
  cohort = NULL,
  by = YEAR,
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
  non-empty and unique. For `output = "summary"`, can also be the result
  of
  [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
  with `.codes`. Omit `type` and `system` in that case.

- cohort:

  Optional tidy-evaluation logical expression defining the cohort. Rows
  where it evaluates to `NA` are excluded.

- by:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  One or more columns defining periods. Defaults to `YEAR`. Use
  name-based selectors on DuckDB queries.

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

To reuse code criteria from
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
pass its result as `codes`. The audit uses each criterion's recorded
code definition, system, and position. It counts each code criterion
independently within the audit sample. Supply `cohort` to restrict that
sample. Ordinary logical criteria and design exclusions from the
attrition table are not applied.

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

[Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.html),
[Code transitions and
sensitivity](https://msaadasif.github.io/easyNIS/articles/code-transitions.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
nis <- nis_open(nis_example(2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpUnGnxo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpUnGnxo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_audit_code_transition(nis, codes = c(heart_failure = "I50"))
#> # A tibble: 2 × 7
#>    YEAR code_group   n_cohort_unweighted n_unweighted n_weighted pct_within_year
#>   <int> <chr>                      <int>        <int>      <dbl>           <dbl>
#> 1  2019 heart_failu…                  96            0          0               0
#> 2  2020 heart_failu…                  96            0          0               0
#> # ℹ 1 more variable: yoy_pct_change <dbl>
nis_audit_code_transition(nis, codes = c(heart_failure = "I50"),
                          by = c(YEAR, DQTR), output = "inventory")
#> # A tibble: 8 × 8
#>    YEAR  DQTR code_group    code  n_cohort_unweighted n_unweighted n_weighted
#>   <int> <int> <chr>         <chr>               <int>        <int>      <dbl>
#> 1  2019     1 heart_failure NA                     24            0          0
#> 2  2019     2 heart_failure NA                     24            0          0
#> 3  2019     3 heart_failure NA                     24            0          0
#> 4  2019     4 heart_failure NA                     24            0          0
#> 5  2020     1 heart_failure NA                     24            0          0
#> 6  2020     2 heart_failure NA                     24            0          0
#> 7  2020     3 heart_failure NA                     24            0          0
#> 8  2020     4 heart_failure NA                     24            0          0
#> # ℹ 1 more variable: status <chr>
```
