# Add procedure prefix flags

Each procedure slot is checked separately, with the same prefix rules,
byte for byte comparison, and `system` semantics as
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md).
`"icd10"` reads `I10_PR1`, ...; `"icd9"` (experimental) reads `PR1`, ...
Prefixes only match slots of the chosen system, so a flag over a mixed
2015 query is `FALSE` on discharges coded in the other system.

## Usage

``` r
nis_flag_pr(
  .data,
  ...,
  position = c("any", "principal"),
  system = c("icd10", "icd9")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- ...:

  Named flag definitions, such as `ablation = "02L"`.

- position:

  Slots to check: all slots or the principal slot only.

- system:

  Code system of the slots to check: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

## Value

`.data` with one logical column per named definition.

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
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHvwyWX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHvwyWX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpHvwyWX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |>
  nis_flag_pr(ablation = "02L") |>
  dplyr::count(ablation) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   ablation     n
#>   <lgl>    <dbl>
#> 1 FALSE      144
#> 2 TRUE        48
```
