# Suppress small unweighted cells in a survey summary

For a
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
result, replaces displayed statistics when their corresponding
unweighted count is at or below `threshold`. Counts come from the
`cards` computed by
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).
Continuous2 statistic rows use the non-missing count for their
corresponding output column. If that count is absent, ambiguous, or
non-finite for a displayed statistic, the function errors; blank
statistic cells do not require a count. When a by-group cell is masked,
the overall cell (`stat_0`) in the same row is marked `Masked`, unless
its own count is at or below the threshold. Other derivable cells still
need analyst review before sharing. This route checks discharge counts
only; it cannot apply the two-hospital rule. Use
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
with the data-frame route to apply both disclosure rules.

## Usage

``` r
nis_suppress(
  x,
  threshold = 10,
  ...,
  count_col,
  weighted_cols = NULL,
  by = NULL,
  secondary = TRUE,
  hospital_col = NULL
)
```

## Arguments

- x:

  A
  [`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
  result, optionally with `add_p()` or `add_overall()`, or a data
  frame/tibble.

- threshold:

  Maximum unweighted cell count to suppress.

- ...:

  Reserved for compatibility; unused arguments are errors.

- count_col:

  For data frames, the unweighted-count column name (required).

- weighted_cols:

  For data frames, other columns to mask on primary and secondary rows.

- by:

  Optional data-frame grouping column names defining strata for
  complementary suppression.

- secondary:

  Apply complementary suppression. For data frames this masks the
  smallest remaining positive count when exactly one row in a stratum is
  primary-masked. This is single-dimension complementary suppression,
  not a full cell-suppression solver; totals rows must be handled or
  excluded by the user.

- hospital_col:

  Optional data-frame column containing the number of distinct
  contributing hospitals for each cell. Cells with fewer than two
  hospitals are marked `<2 hospitals`. Missing or invalid hospital
  counts are errors. Hospital identifiers must be counted by year;
  [`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
  computes counts from record-level data or an
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  result.

## Value

For data frames, the same table with masked columns converted to
character. For `gtsummary` results, the table with primary and secondary
masks and a footnote describing them.

## See also

[Disclosure and
suppression](https://msaadasif.github.io/easyNIS/reference/articles/disclosure.md).

Other disclosure:
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEjnBNk/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEjnBNk/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEjnBNk/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.
table <- gtsummary::tbl_svysummary(
  design,
  by = RACE,
  include = c(AGE, FEMALE)
)
nis_suppress(table, threshold = 10)
#> `nis_suppress()` on a `tbl_svysummary` checks discharge counts only; it does
#> not apply the two-hospital rule.


  

Characteristic
```
