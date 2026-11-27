# Count discharges and contributing hospitals by cell

Count sampled discharges and distinct hospital-years for each cell. Rows
need valid hospital and year identifiers. A DuckDB input returns only
grouped counts to R.

## Usage

``` r
nis_cell_counts(.data, by = NULL)
```

## Arguments

- .data:

  Record-level data frame, lazy DuckDB query, or result of
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

- by:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Cell-defining columns. Omit or select no columns for overall counts.
  Use name-based selectors on DuckDB queries. The summary names `n` and
  `hospitals` are reserved.

## Value

A data frame with the columns in `by`, `n` (unweighted discharges), and
`hospitals` (distinct year-scoped hospitals).

## See also

[Check disclosure before sharing
results](https://msaadasif.github.io/easyNIS/articles/disclosure.html),
[Check disclosure before sharing
results](https://msaadasif.github.io/easyNIS/articles/disclosure.html).

Other disclosure:
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)

## Examples

``` r
nis <- nis_open(nis_example(2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpDuFgaD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpDuFgaD/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_cell_counts(nis, by = DQTR)
#> # A tibble: 4 × 3
#>    DQTR     n hospitals
#>   <int> <dbl>     <dbl>
#> 1     1    24        12
#> 2     2    24        12
#> 3     3    24        12
#> 4     4    24        12
```
