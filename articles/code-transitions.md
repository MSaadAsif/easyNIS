# Code transitions and sensitivity

## Audit code frequencies

[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md)
summarizes named code groups by period. The example is a small invented
data frame; use separate calls for ICD-9 and ICD-10 because the function
matches only one code system at a time.

``` r

toy <- data.frame(
  YEAR = rep(2018:2020, each = 2),
  I10_DX1 = c("I5022", "E119", "I509", "E119", "I5022", "E119"),
  DISCWT = rep(1, 6)
)
nis_audit_code_transition(
  toy,
  codes = c(heart_failure = "I50", diabetes = "E11"),
  type = "dx"
)
#> # A tibble: 6 × 7
#>    YEAR code_group   n_cohort_unweighted n_unweighted n_weighted pct_within_year
#>   <int> <chr>                      <int>        <int>      <dbl>           <dbl>
#> 1  2018 heart_failu…                   2            1          1              50
#> 2  2019 heart_failu…                   2            1          1              50
#> 3  2020 heart_failu…                   2            1          1              50
#> 4  2018 diabetes                       2            1          1              50
#> 5  2019 diabetes                       2            1          1              50
#> 6  2020 diabetes                       2            1          1              50
#> # ℹ 1 more variable: yoy_pct_change <dbl>
```

The output gives unweighted and weighted group counts and each group’s
share of all discharges within the period. A year-over-year percentage
change is relative to the prior observed period; it is descriptive and
does not explain why coding prevalence changed.

## Compare diagnosis positions

Principal and secondary diagnoses can capture different presentations.
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md)
compares counts and selected outcome rates across principal,
secondary-only, and any-position definitions.

``` r

nis <- nis_open(nis_example(years = 2019))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpTPPcYQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpTPPcYQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_dx_sensitivity(nis, "I50")
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> # A tibble: 3 × 9
#>   presentation n_unweighted n_weighted pct_of_any_unweighted pct_of_any_weighted
#>   <chr>               <dbl>      <dbl>                 <dbl>               <dbl>
#> 1 principal              54       62.4                   100                 100
#> 2 secondary_o…            0        0                       0                   0
#> 3 any                    54       62.4                   100                 100
#> # ℹ 4 more variables: DIED_rate_unweighted <dbl>, DIED_rate_weighted <dbl>,
#> #   ELECTIVE_rate_unweighted <dbl>, ELECTIVE_rate_weighted <dbl>
```

The rows show how the synthetic definition changes with diagnosis
position. These are descriptive weighted summaries, not survey estimates
with standard errors. Use a survey design for inferential comparisons.

## Handle the ICD transition

NIS changed from ICD-9-CM to ICD-10-CM/PCS in October 2015. 2015
combines ICD-9 discharges from Q1–Q3 with ICD-10 discharges from Q4.
Flag the systems separately using the appropriate slot names and version
information; easyNIS does not supply a crosswalk or clinical equivalence
decisions. ICD-9 helpers and code-system boundary checks are
experimental.

## Common pitfalls

> **Common pitfalls**
>
> - A trend break can reflect code-set changes, case mix, or practice as
>   well as a true change in prevalence.
> - A zero in an audit means no match in the selected system, not
>   absence in a different code system.
> - Principal and any-position summaries are nested definitions, not
>   independent groups.

See
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
and
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md).
