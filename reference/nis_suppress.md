# Suppress small unweighted cells in a survey summary

For a
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
result, replaces displayed statistics when their corresponding
unweighted count is at or below `threshold`. The count is the smaller of
the summary card count and the number of matching records in the
supplied survey design. A dichotomous row whose displayed level passes
both rules is marked `Masked` if its non-missing complement fails the
count or hospital rule. Continuous2 statistic rows use the non-missing
count for their corresponding output column. If that count is absent,
ambiguous, or non-finite for a displayed statistic, the function errors;
blank statistic cells do not require a count. When a by-group cell is
masked, the overall cell (`stat_0`) in the same row is marked `Masked`,
unless it already has a primary mask. If exactly one categorical level
is masked within a column, the smallest remaining positive level is also
marked `Masked`. Other derivable cells still need analyst review before
sharing. For survey summaries, hospital support is counted from retained
records using year-scoped `YEAR` and `HOSP_NIS` identities, within the
cohort, non-missing/category, and by-group cells represented by the
table. The rule is applied only when the survey records and summary
cards provide an unambiguous mapping; otherwise the function errors.
Data-frame behavior uses the supplied `count_col` and optional
`hospital_col` as described below.

## Usage

``` r
nis_suppress(
  .data,
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

- .data:

  A
  [`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
  result, optionally with `add_p()` or `add_overall()`, or a data
  frame/tibble.

- threshold:

  Maximum unweighted cell count to suppress.

- ...:

  Reserved for compatibility; unused arguments are errors.

- count_col:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  For data frames, select exactly one unweighted-count column.

- weighted_cols:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  For data frames, other columns to mask on primary and secondary rows.

- by:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Optional data-frame grouping columns defining strata for complementary
  suppression.

- secondary:

  Apply complementary suppression. For data frames this masks the
  smallest remaining positive count when exactly one row in a stratum is
  primary-masked. This is single-dimension complementary suppression,
  not a full cell-suppression solver; totals rows must be handled or
  excluded by the user.

- hospital_col:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Optional selection of a single data-frame column containing the number
  of distinct contributing hospitals for each cell. Cells with fewer
  than two hospitals are marked `<2 hospitals`. Missing or invalid
  hospital counts are errors. Hospital identifiers must be counted by
  year;
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
suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.html).

Other disclosure:
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEkIRZU/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEkIRZU/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
#> Preparing the cohort survey design.
table <- gtsummary::tbl_svysummary(
  design,
  by = RACE,
  include = c(AGE, FEMALE)
)
nis_suppress(table, threshold = 10)


  

Characteristic
```
