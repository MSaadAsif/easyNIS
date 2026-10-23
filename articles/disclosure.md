# Disclosure and suppression

HCUP’s reporting rules prohibit reporting cells with 10 or fewer
discharges and require that reported estimates represent at least two
hospitals. Follow the terms of the applicable Data Use Agreement and
institutional review. Suppression is a review aid, not a guarantee
against every disclosure path.

## Count data-frame cells

[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
counts unweighted discharges and distinct hospitals using year-scoped
hospital IDs. This invented fixture has one cell with a small count and
a separate cell with more than 10 discharges but support from only one
hospital.

``` r

records <- data.frame(
  YEAR = rep(2020, 14),
  HOSP_NIS = c(1, 1, 2, rep(3, 11)),
  group = c(rep("A", 3), rep("B", 11)),
  estimate = c(rep(2.1, 3), rep(8.4, 11))
)
cell_estimates <- dplyr::summarise(
  dplyr::group_by(records, group),
  estimate = mean(estimate),
  .groups = "drop"
)
cells <- nis_cell_counts(records, by = "group") |>
  dplyr::left_join(cell_estimates, by = "group")
cells
#> # A tibble: 2 × 4
#>   group     n hospitals estimate
#>   <chr> <int>     <int>    <dbl>
#> 1 A         3         2      2.1
#> 2 B        11         1      8.4
```

`A` has three discharges across two hospitals; `B` has 11 discharges at
one hospital. Counts are unweighted and the displayed `estimate` is only
a made-up value.

## Suppress data frames

For data frames, provide the count column and any estimate columns to
mask. The default threshold is inclusive: counts at or below 10 are
suppressed. Cells with fewer than two hospitals are marked as such.

``` r

nis_suppress(
  cells,
  count_col = "n",
  weighted_cols = "estimate",
  hospital_col = "hospitals"
)
#> # A tibble: 2 × 4
#>   group n            hospitals    estimate    
#>   <chr> <chr>        <chr>        <chr>       
#> 1 A     ≤10          ≤10          ≤10         
#> 2 B     <2 hospitals <2 hospitals <2 hospitals
```

The output suppresses `A` under the inclusive ≤10 discharge rule and
marks `B` under the two-hospital rule, despite its count being above 10.
When a table has totals or grouped subtotals, inspect them for
complementary disclosure.

## Suppress a gtsummary table

For a
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
object,
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
reads unweighted counts from the table’s cards, masks displayed
statistics at or below the threshold, and marks the overall statistic in
the same row. This route checks discharge counts only; it cannot check
the two-hospital rule.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpRIk3A8/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpRIk3A8/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, heart_failure, keep = c(AGE, FEMALE, RACE))
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
table_one <- gtsummary::tbl_svysummary(
  design,
  by = RACE,
  include = c(AGE, FEMALE)
)
nis_suppress(table_one, threshold = 10)
#> `nis_suppress()` on a `tbl_svysummary` checks discharge counts only; it does
#> not apply the two-hospital rule.
```

[TABLE]

The masked table is a starting point for review. Use the data-frame
route with
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
when both the discharge threshold and hospital count must be checked.

## Common pitfalls

> **Common pitfalls**
>
> - Suppressing only values below 10 misses the prohibited count of
>   exactly 10; the default masks 10 and below.
> - A single-hospital cell needs review even when its discharge count is
>   large.
> - Masking a cell can leave it derivable from totals, subtotals, or
>   another table. Review the complete set of planned outputs.

See
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
and
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md).
