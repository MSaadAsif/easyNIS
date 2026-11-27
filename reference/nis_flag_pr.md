# Add procedure code flags

Flag discharges whose procedure codes match your clinical definition.

## Usage

``` r
nis_flag_pr(
  .data,
  ...,
  position = c("any", "principal"),
  system = c("icd10", "icd9", "both")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- ...:

  Named flag definitions, such as `ablation = "02L"`; see
  [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
  for list definitions with exclusions or regexes.

- position:

  Slots to check: all slots or the principal slot only.

- system:

  Code system of the slots to check: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015), or `"both"` (experimental).

## Value

`.data` with one logical column per named definition.

## Details

Use the
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
rules for prefixes, exact exclusions, regular expressions, and mixed
coding eras. For ICD-10 the slots are `I10_PR1`, `I10_PR2`, and so on.
For ICD-9 they are `PR1`, `PR2`, and so on. Use `position = "principal"`
to check slot 1 only.

## See also

[Define and save a
cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzylRu1/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzylRu1/duckdb
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
