# Flag procedure timing relative to an index procedure

Flag an outcome procedure that falls within a specified time relation to
an index procedure.

## Usage

``` r
nis_flag_pr_timing(
  .data,
  index_pr,
  outcome_pr,
  name = "outcome_post_index",
  relation = c("on_or_after", "after", "before", "same_day", "within_days"),
  window = NULL,
  missing_day = c("exclude", "assume_same_day", "indeterminate"),
  system = c("icd10", "icd9", "both")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query.

- index_pr:

  Code definition for the index procedure, as in
  [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).

- outcome_pr:

  Code definition for the outcome procedure, as in
  [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).

- name:

  Single name for the new logical flag.

- relation:

  Timing relation: on_or_after, after, before, same_day, or within_days.

- window:

  Required non-negative integer for within_days; otherwise NULL.

- missing_day:

  How to handle unknown days: exclude returns FALSE, assume_same_day
  uses day 0, and indeterminate returns NA unless a determinate match is
  TRUE.

- system:

  Code system: icd10 uses I10_PR followed by a slot number; icd9 uses PR
  followed by a slot number. With `system = "both"`, supply named `icd9`
  and `icd10` definitions for each procedure.

## Value

.data with the logical column named by name.

## Details

Each procedure uses the day from its corresponding PRDAY slot. Use the
prefix, full-code regular expression, and exact exclusion rules of
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).
Timing compares slots within the same code system. The earliest known
index day is the reference. When either procedure is absent, the flag is
false. When both occur and a match cannot be determined because a day is
missing, non-finite, or negative, `missing_day` sets the handling. The
`within_days` window starts on the index day and includes both
endpoints.

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
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)

## Examples

``` r
nis <- nis_open(nis_example(2020)) |>
  dplyr::mutate(PRDAY1 = 0L, PRDAY2 = 1L) |>
  nis_flag_pr_timing("0270", "02L73", relation = "after")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbD2WgP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpbD2WgP/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(outcome_post_index) |> dplyr::collect()
#> # A tibble: 2 × 2
#>   outcome_post_index     n
#>   <lgl>              <dbl>
#> 1 FALSE                 84
#> 2 TRUE                  12
```
