# Suppress small unweighted cells in a survey summary

Mask a summary using unweighted counts and contributing hospitals.

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

## Details

In a survey table, each statistic is checked against its supporting
discharges and hospital-years. The function stops when it cannot
identify the records behind a statistic. It also checks the non-missing
complement of a displayed two-level indicator and can mask related
overall statistics. If one categorical level in a column is masked, the
function also masks the smallest remaining positive level. Review other
deductions from related outputs before release.

In a data frame, supply unweighted counts and, when available, distinct
hospital counts. Grouped complementary suppression can mask an
additional positive cell when there is one primary mask in a group.
Review totals and any other cells that someone could recover by
subtraction.

## See also

[Check disclosure before sharing
results](https://msaadasif.github.io/easyNIS/articles/disclosure.html),
[Check disclosure before sharing
results](https://msaadasif.github.io/easyNIS/articles/disclosure.html).

Other disclosure:
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpcFxJEW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpcFxJEW/duckdb
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
