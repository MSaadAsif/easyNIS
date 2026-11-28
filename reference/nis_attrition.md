# Count discharges at each eligibility step

Count the discharges that remain after each eligibility criterion.

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

## Details

Evaluate criteria in order over the ungrouped input. Missing criteria
exclude a discharge. Missing weights contribute zero to weighted counts.
Use `.design = TRUE` when the same criteria will define a survey cohort.
Use `nis_attrition_cohort()` to reuse the combined expression.

## See also

[Define and save a
cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)

## Examples

``` r
nis <- nis_open(nis_example(2020))
flow <- nis_attrition(nis, adult = AGE >= 18, older = AGE >= 65, .design = TRUE)
flow
#> # A tibble: 3 × 7
#>    step criterion               n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                          <int>                <int>      <dbl>
#> 1     0 Valid design discharges           96                   NA      114. 
#> 2     1 adult                             96                    0      114. 
#> 3     2 older                             44                   52       52.5
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
nis_design(nis, cohort = !!nis_attrition_cohort(flow), keep = LOS)
#> Stratified 1 - level Cluster Sampling design (with replacement)
#> With (12) clusters.
#> Called via srvyr
#> Data variables: 
#>   - YEAR (int), HOSP_NIS (int), NIS_STRATUM (int), DISCWT (dbl), LOS (dbl)
```
