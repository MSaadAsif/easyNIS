# Summarize procedure-day completeness by year and procedure slot

Counts matched procedure slots with known, missing, negative/sentinel,
or absent PRDAY values. Prefix matching and day classification follow
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
and
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md);
only slots whose procedure code matches `pr` are counted. Counts are
unweighted discharge-slot counts. This is a descriptive completeness
summary: it does not impute days or judge whether the observed
completeness is acceptable.

## Usage

``` r
nis_audit_prday(.data, pr, system = c("icd10", "icd9"))
```

## Arguments

- .data:

  A data frame or lazy DuckDB query with `YEAR`.

- pr:

  Character vector of procedure code prefixes, normalized and matched
  under the same rules as
  [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).

- system:

  Code system: `"icd10"` uses `I10_PR<n>` (default); `"icd9"` uses
  `PR<n>`.

## Value

An in-memory tibble with one row per year and procedure slot.
`matched_slots` counts matching procedure slots; `known_day`,
`missing_day`, `sentinel_invalid_day`, and `absent_prday_column`
partition those matches. `pct_known` is
`100 * known_day / matched_slots`, or `NA` when there are no matched
slots. A PRDAY column is considered absent when it is absent from the
input query's schema. A unified multi-file query does not retain
source-file field presence by year. A value that does not decode to a
finite number counts as missing. Factor days use their labels. Negative
finite days (including HCUP sentinels) count as sentinel/invalid,
matching
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md).

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
nis <- nis_open(nis_example(2020)) |>
  dplyr::mutate(PRDAY1 = 0L, PRDAY2 = 1L)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpq6Jh4y/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpq6Jh4y/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_audit_prday(nis, pr = "0270")
#> # A tibble: 25 × 8
#>     YEAR  slot matched_slots known_day missing_day sentinel_invalid_day
#>    <int> <int>         <int>     <int>       <int>                <int>
#>  1  2020     1            48        48           0                    0
#>  2  2020     2             0         0           0                    0
#>  3  2020     3             0         0           0                    0
#>  4  2020     4             0         0           0                    0
#>  5  2020     5             0         0           0                    0
#>  6  2020     6             0         0           0                    0
#>  7  2020     7             0         0           0                    0
#>  8  2020     8             0         0           0                    0
#>  9  2020     9             0         0           0                    0
#> 10  2020    10             0         0           0                    0
#> # ℹ 15 more rows
#> # ℹ 2 more variables: absent_prday_column <int>, pct_known <dbl>
```
