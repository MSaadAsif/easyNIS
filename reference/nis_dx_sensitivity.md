# Summarize diagnosis-position sensitivity

Summarizes unweighted and weighted presentation counts and outcome rates
for principal, secondary-only, and any-position diagnosis flags. These
are descriptive point estimates, not design-based survey estimates; use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
when standard errors are needed. Small cells must go through
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
before reporting under the HCUP Data Use Agreement, which prohibits
reporting cells of 1–10.

## Usage

``` r
nis_dx_sensitivity(
  .data,
  code,
  system = c("icd10", "icd9"),
  weight_var = "DISCWT",
  outcomes = c("DIED", "ELECTIVE")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- code:

  Non-missing character vector of diagnosis prefixes.

- system:

  Code system of the diagnosis slots: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

- weight_var:

  Name of the discharge weight column. Defaults to `DISCWT`.

- outcomes:

  Outcome columns to summarize. By default, `DIED` and `ELECTIVE` are
  included when present and absent defaults are skipped.

## Value

A collected tibble with one row per presentation and unweighted and
weighted counts, shares of all prefix-positive presentations, and rates
for requested outcomes. The principal presentation is a strict subset of
any-position cases, so Cohen's kappa is not meaningful here.

## See also

[Code transitions and
sensitivity](https://msaadasif.github.io/easyNIS/reference/articles/code-transitions.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md),
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
