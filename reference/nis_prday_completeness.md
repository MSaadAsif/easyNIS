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
nis_prday_completeness(.data, pr, system = c("icd10", "icd9"))
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
source-file field presence by year. When present, `NA` days count as
missing and all negative days (including HCUP sentinels) count as
sentinel/invalid, matching
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md).

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
toy <- data.frame(
  YEAR = c(2020L, 2020L, 2021L),
  I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ"),
  I10_PR2 = c("0JH604Z", "OTHER", "0JH604Z"),
  PRDAY1 = c(0L, -99L, 1L), PRDAY2 = c(1L, NA_integer_, -88L)
)
nis_prday_completeness(toy, c("02UG0", "0JH60"))
#> # A tibble: 4 × 8
#>    YEAR  slot matched_slots known_day missing_day sentinel_invalid_day
#>   <int> <int>         <int>     <int>       <int>                <int>
#> 1  2020     1             2         1           0                    1
#> 2  2020     2             1         1           0                    0
#> 3  2021     1             1         1           0                    0
#> 4  2021     2             1         0           0                    1
#> # ℹ 2 more variables: absent_prday_column <int>, pct_known <dbl>
```
