# Attach an annual NIS companion to Core discharges

Add selected companion fields to a lazy Core query.

## Usage

``` r
nis_join_companion(.data, path, component, columns)
```

## Arguments

- .data:

  A lazy Core query from
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
  including its linkage fields.

- path:

  Directory containing Parquet for one companion component, using the
  annual or Hive layout accepted by
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).
  Keep Core and each companion in separate directories, with parts from
  the same release.

- component:

  One of `"hospital"`, `"severity"`, or `"dx_pr_grps"`.

- columns:

  \<[tidy-select](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Select one or more companion fields by name across the selected years.
  Linkage keys are included automatically and are outside the selection.
  Use the field's source spelling for bare names or
  [`all_of()`](https://tidyselect.r-lib.org/reference/all_of.html).
  Selected fields keep their source names and must have names distinct
  from fields in `.data`.

## Value

A lazy DuckDB-backed Core query with the requested columns added.

## Details

Join Hospital data on `YEAR` and `HOSP_NIS`. Join Severity or Diagnosis
and Procedure Groups data on `YEAR` and `KEY_NIS`. Use the same release
for each annual Core and companion part. Unmatched discharges remain in
the result with missing companion values. Hospital `TOTAL_DISC` counts
sampled discharges and is excluded. The joined records still represent
discharges.

## See also

[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html),
[Opening NIS
data](https://msaadasif.github.io/easyNIS/articles/opening-data.html),
[HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp).

## Examples

``` r
nis <- nis_open(nis_example(2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpf1sxLd/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpf1sxLd/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
hospitals <- nis |>
  dplyr::distinct(HOSP_NIS, beds = HOSP_BEDSIZE) |>
  dplyr::collect()

path <- tempfile()
dir.create(path)
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpf1sxLd/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
DBI::dbWriteTable(con, "hospitals", hospitals)
file <- DBI::dbQuoteString(con, file.path(path, "NIS_2020.parquet"))
DBI::dbExecute(con, paste("COPY hospitals TO", file, "(FORMAT PARQUET)"))
#> [1] 12
DBI::dbDisconnect(con, shutdown = TRUE)

nis |>
  nis_join_companion(path, "hospital", beds) |>
  dplyr::count(beds) |>
  dplyr::collect()
#> # A tibble: 3 × 2
#>    beds     n
#>   <int> <dbl>
#> 1     1    32
#> 2     2    32
#> 3     3    32
```
