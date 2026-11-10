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

## Group by several period columns

`by` accepts more than one column. A period is then an observed
combination, such as year and quarter, sorted in the order given. A
period with a missing component is kept as its own row after the
complete periods. No unambiguous year comparison exists for several
columns, so `yoy_pct_change` is `NA` in every row; compare
`pct_within_year` across the periods you choose.

``` r

toy$DQTR <- rep(c(1L, 2L), times = 3)
toy$DQTR[6] <- NA
nis_audit_code_transition(
  toy,
  codes = c(heart_failure = "I50"),
  type = "dx",
  by = c("YEAR", "DQTR")
)
#> # A tibble: 6 × 8
#>    YEAR  DQTR code_group    n_cohort_unweighted n_unweighted n_weighted
#>   <int> <int> <chr>                       <int>        <int>      <dbl>
#> 1  2018     1 heart_failure                   1            1          1
#> 2  2018     2 heart_failure                   1            0          0
#> 3  2019     1 heart_failure                   1            1          1
#> 4  2019     2 heart_failure                   1            0          0
#> 5  2020     1 heart_failure                   1            1          1
#> 6  2020    NA heart_failure                   1            0          0
#> # ℹ 2 more variables: pct_within_year <dbl>, yoy_pct_change <dbl>
```

## Inventory observed codes

`output = "inventory"` lists the full codes that matched each prefix
group, with counts for every period. `status` marks a code `absent` when
a period has no matches and `sparse` when its unweighted count is at
most `sparse_n` (default 10). A group that matches no observed code
appears once per period with a missing `code`. The counts are aggregate,
so apply your disclosure rules before sharing them.

``` r

nis_audit_code_transition(
  toy,
  codes = c(heart_failure = "I50", diabetes = "E11"),
  type = "dx",
  output = "inventory"
)
#> # A tibble: 9 × 7
#>    YEAR code_group    code  n_cohort_unweighted n_unweighted n_weighted status
#>   <int> <chr>         <chr>               <int>        <int>      <dbl> <chr> 
#> 1  2018 heart_failure I5022                   2            1          1 sparse
#> 2  2019 heart_failure I5022                   2            0          0 absent
#> 3  2020 heart_failure I5022                   2            1          1 sparse
#> 4  2018 heart_failure I509                    2            0          0 absent
#> 5  2019 heart_failure I509                    2            1          1 sparse
#> 6  2020 heart_failure I509                    2            0          0 absent
#> 7  2018 diabetes      E119                    2            1          1 sparse
#> 8  2019 diabetes      E119                    2            1          1 sparse
#> 9  2020 diabetes      E119                    2            1          1 sparse
```

## Compare diagnosis positions

Principal and secondary diagnoses can capture different presentations.
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md)
compares counts and selected outcome rates across principal,
secondary-only, and any-position definitions.

``` r

nis <- nis_open(nis_example(years = 2019))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp84kyAF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp84kyAF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_dx_sensitivity(nis, "I50")
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
> - An `absent` or `sparse` inventory status describes this dataset and
>   cohort; it does not show that a code is unused.
> - Principal and any-position summaries are nested definitions, not
>   independent groups.

See
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
and
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md).
