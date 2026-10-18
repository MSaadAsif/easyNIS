# Flag procedure timing relative to an index procedure

Compares procedure slots with the correspondingly numbered PRDAY values.
The earliest valid index day is used when the index procedure occurs in
multiple slots. A slot matching both prefix sets counts as both
procedures. Prefixes follow the normalization and matching rules of
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).
Negative days (including HCUP sentinel values) and missing days are
unknown. If either procedure is absent, the result is FALSE. Otherwise,
any outcome with a known day satisfying the relation returns TRUE. If
none does and a matching procedure has an unknown day, exclude returns
FALSE, assume_same_day treats that day as 0, and indeterminate returns
NA.

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
  system = c("icd10", "icd9")
)
```

## Arguments

- .data:

  A data frame or lazy Arrow query.

- index_pr:

  Character vector of index procedure code prefixes.

- outcome_pr:

  Character vector of outcome procedure code prefixes.

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

  Code system: icd10 uses I10_PR; icd9 uses PR.

## Value

.data with the logical column named by name.

## Details

on_or_after tests outcome day \>= earliest index day; after tests \>;
before tests \<; same_day tests equality. within_days tests whether the
outcome is from 0 through window days after the earliest index day,
inclusive.

## Examples

``` r
toy <- data.frame(I10_PR1 = c("02UG0JZ", "0JH604Z"), PRDAY1 = c(0L, 1L))
nis_flag_pr_timing(toy, "02UG0", "0JH60")
#>   I10_PR1 PRDAY1 outcome_post_index
#> 1 02UG0JZ      0              FALSE
#> 2 0JH604Z      1              FALSE
```
