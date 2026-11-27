# Add diagnosis code flags

Flag discharges whose diagnosis codes match your clinical definition.

## Usage

``` r
nis_flag_dx(
  .data,
  ...,
  position = c("any", "principal", "secondary"),
  system = c("icd10", "icd9", "both")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- ...:

  Named flag definitions, such as `heart_failure = "I50"`. For
  exclusions or full-code patterns, use a list such as
  `heart_failure = list(prefix = "I50", exclude = "I502")` or
  `heart_failure = list(regex = "I50(1|2)")`. Within a list, `prefix`,
  `regex`, and `exclude` can each be character vectors. Prefix and regex
  matches are combined; exclusions are exact and apply within each slot.
  With `system = "both"`, nest those definitions under `icd9` and
  `icd10`, for example `flag = list(icd9 = "428", icd10 = "I50")`.

- position:

  Slots to check: all slots, the principal slot, or secondary slots
  only.

- system:

  Code system of the slots to check: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015), or `"both"` (experimental).

## Value

`.data` with one logical column per named definition.

## Details

Supply prefixes or a list of `prefix`, `regex`, and `exclude`. Regular
expressions match the whole stored code. An exclusion removes an exact
code from the match in that slot. Another diagnosis slot can still set
the flag. Specify `position = "principal"` to search slot 1 only. Use
separate definitions and `system = "both"` for mixed coding eras.

## See also

[Define and save a
cohort](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9MfXAY/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9MfXAY/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |>
  nis_flag_dx(heart_failure = "I50") |>
  dplyr::count(heart_failure) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   heart_failure     n
#>   <lgl>         <dbl>
#> 1 FALSE            84
#> 2 TRUE            108

# Several prefixes, restricted to the principal diagnosis
nis |>
  nis_flag_dx(hf_or_diabetes = c("I50", "E11"), position = "principal") |>
  dplyr::count(hf_or_diabetes) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   hf_or_diabetes     n
#>   <lgl>          <dbl>
#> 1 FALSE             84
#> 2 TRUE             108

# Exclude one exact subcode or match full codes with a regular expression
nis |>
  nis_flag_dx(hf_other = list(prefix = "I50", exclude = "I501")) |>
  dplyr::count(hf_other) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   hf_other     n
#>   <lgl>    <dbl>
#> 1 FALSE       84
#> 2 TRUE       108
nis |>
  nis_flag_dx(hf_full = list(regex = "I50[0-9]{2}")) |>
  dplyr::count(hf_full) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp9MfXAY/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 2 × 2
#>   hf_full     n
#>   <lgl>   <dbl>
#> 1 FALSE      84
#> 2 TRUE      108
```
