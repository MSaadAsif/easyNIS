# Add diagnosis position flags

Adds flags for a diagnosis prefix in the principal position, secondary
positions only, and any position. Prefix matching and code-system
eligibility follow
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md).

## Usage

``` r
nis_flag_dx_position(.data, code, name = "dx", system = c("icd10", "icd9"))
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- code:

  Non-missing character vector of diagnosis prefixes.

- name:

  Base name for the added columns. The function adds `<name>_principal`,
  `<name>_secondary_only`, and `<name>_any`.

- system:

  Code system of the diagnosis slots: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

## Value

`.data` with three logical diagnosis-position columns.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmphFGx8n/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmphFGx8n/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_flag_dx_position(nis, "I50", name = "heart_failure")
#> # A query:  ?? x 111
#> # Database: DuckDB 1.5.6 [unknown@Linux 6.17.0-1022-azure:R 4.6.1/:memory:]
#>      AGE AGE_NEONATE AMONTH APRDRG_RISK_MORTALITY APRDRG_SEVERITY AWEEKEND
#>    <dbl>       <int>  <int>                 <int>           <int>    <int>
#>  1    28           0      3                     2               3        0
#>  2    35           0      4                     3               4        0
#>  3    42           0      5                     4               0        0
#>  4    49           0      6                     0               1        0
#>  5    56           0      7                     1               2        0
#>  6    63           0      8                     2               3        1
#>  7    70           0      9                     3               4        1
#>  8    77           0     10                     4               0        0
#>  9    31           0      4                     3               4        0
#> 10    38           0      5                     4               0        0
#> # ℹ more rows
#> # ℹ 105 more variables: CCR_NIS <dbl>, DIED <int>, DISCWT <dbl>,
#> #   DISPUNIFORM <dbl>, DQTR <int>, DRG_NOPOA <int>, ELECTIVE <int>,
#> #   FEMALE <int>, HCUP_ED <int>, HOSP_BEDSIZE <int>, HOSP_DIVISION <int>,
#> #   HOSP_LOCTEACH <int>, HOSP_NIS <int>, HOSP_REGION <int>, H_CONTRL <int>,
#> #   I10_BIRTH <int>, I10_DELIVERY <int>, I10_DX1 <chr>, I10_DX10 <chr>,
#> #   I10_DX11 <chr>, I10_DX12 <chr>, I10_DX13 <chr>, I10_DX14 <chr>, …
```
