# Add diagnosis prefix flags

Each diagnosis slot is checked separately. Supplied prefixes are
case-insensitive, and periods and spaces in them are ignored. Slot
values are compared as stored, case sensitively, because NIS stores
upper-case codes without periods. Matching stays lazy in DuckDB and
avoids per-row text normalization.

## Usage

``` r
nis_flag_dx(
  .data,
  ...,
  position = c("any", "principal", "secondary"),
  system = c("icd10", "icd9")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- ...:

  Named flag definitions, such as `heart_failure = "I50"`.

- position:

  Slots to check: all slots, the principal slot, or secondary slots
  only.

- system:

  Code system of the slots to check: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

## Value

`.data` with one logical column per named definition.

## Details

`system` picks which slots are tested. `"icd10"` reads `I10_DX1`,
`I10_DX2`, ...; `"icd9"` (experimental) reads `DX1`, `DX2`, ... as
stored in NIS 2012 through Q3 2015. A prefix is only ever compared with
slots of the chosen system, so an ICD-10 flag never matches an ICD-9
slot and the reverse.

In 2015 the Q1-Q3 discharges carry ICD-9 codes and the Q4 discharges
carry ICD-10 codes. HCUP is understood to recommend `DXVER` (9 or 10) to
distinguish them, because `DQTR` can be missing (UNVERIFIED:
secondhand); `PRVER` describes the procedure system. Non-missing version
indicators must agree with `system`; non-missing `YEAR` and, in 2015,
`DQTR` must also agree. Conflicting or invalid indicators yield `FALSE`.
Missing indicators rely on the slot namespace: callers must preserve the
official names and leave inapplicable slots missing. Shared slots
containing both systems are not supported. `FALSE` means "not flagged
under that code system", not "condition absent". A study that crosses
October 2015 needs analyst-supplied code sets for both systems, flagged
in two calls and combined, for example
`nis_flag_dx(hf10 = "I50") |> nis_flag_dx(hf9 = "428", system = "icd9") |> dplyr::mutate(hf = hf10 | hf9)`.
easyNIS ships no code lists and no ICD-9 to ICD-10 crosswalk, and even
with both code sets, counts of a condition can break at the transition.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
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
```
