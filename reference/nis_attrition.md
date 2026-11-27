# Summarize sequential cohort attrition

Applies logical criteria cumulatively and reports remaining and dropped
discharge counts at each step. The initial row has no preceding step, so
its dropped counts are `NA`. Criteria are evaluated in order; `NA`
values are treated as excluded, matching
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html).
The summary is aggregated lazily for DuckDB queries and returned as a
collected tibble. Missing weights (including `NaN`) contribute zero to
weighted totals. Existing input groups are ignored, including when
evaluating criteria. Criteria are evaluated over the full input before
annual aggregation.

## Usage

``` r
nis_attrition(
  .data,
  ...,
  by_year = FALSE,
  weight_var = "DISCWT",
  .design = FALSE,
  .codes = NULL
)

nis_attrition_cohort(flow)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- ...:

  Named logical expressions applied cumulatively. Unnamed expressions
  use their deparsed text as the criterion label.

- by_year:

  If `TRUE`, calculate each step within `YEAR`.

- weight_var:

  Name of the discharge weight column. Defaults to `"DISCWT"`.

- .design:

  If `TRUE`, count only discharges with valid survey design fields,
  using the policy in
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
  Criteria still evaluate over the full ungrouped input. Use
  `cohort = !!nis_attrition_cohort(flow)` with the same input to build
  the survey design from the rules in `flow`. Use deterministic
  criteria, since they are evaluated by both functions.

- .codes:

  Optional named list of code criteria applied after `...`, in list
  order. Each criterion is a list with `type` (`"dx"` or `"pr"`),
  `position`, `system`, and `codes` (one flag definition). See
  [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
  and
  [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
  for the matching rules and definitions. Criterion names must be unique
  across `...` and `.codes`.

- flow:

  Result from `nis_attrition(..., .design = TRUE)`.

## Value

`nis_attrition()` returns a tibble with one initial row (`step = 0`) and
one row per criterion. When `by_year = TRUE`, `YEAR` is the first
column. With `.design = TRUE`, the initial row counts valid design
discharges and the tibble stores the combined cohort expression.
`nis_attrition_cohort()` extracts that expression for injection with
`!!` into `cohort` in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
With `.codes`, `attr(flow, "nis_criteria")` is a tibble of criterion
names and their code type, position, system, and definitions. These
fields are missing for ordinary logical criteria. Pass the flow to
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md)
to summarize its code criteria by period.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
toy_nis <- dplyr::tibble(
  AGE = c(16, 45, 60, 72, 55),
  ELECTIVE = c(1, 1, 0, 1, 1),
  DISCWT = c(5.0, 5.2, 4.8, 5.1, 5.0),
  HOSP_NIS = c(1L, 1L, 2L, 2L, 2L),
  NIS_STRATUM = rep(1L, 5),
  YEAR = rep(2020L, 5)
)
nis_attrition(toy_nis, adult = AGE >= 18, elective = ELECTIVE == 1)
#> # A tibble: 3 × 7
#>    step criterion      n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                 <int>                <int>      <dbl>
#> 1     0 All discharges            5                   NA       25.1
#> 2     1 adult                     4                    1       20.1
#> 3     2 elective                  3                    1       15.3
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
flow <- nis_attrition(toy_nis, adult = AGE >= 18, .design = TRUE)
nis_attrition_cohort(flow)
#> <quosure>
#> expr: ^AGE >= 18
#> env:  0x5b399a1ba730
```
