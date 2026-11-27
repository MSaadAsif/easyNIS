# Open annual NIS Parquet files lazily

Open selected years as a DuckDB query.

## Usage

``` r
nis_open(
  path,
  years = NULL,
  reader = c("duckdb", "arrow"),
  check_release = TRUE
)
```

## Arguments

- path:

  Directory containing `NIS_<year>.parquet` files or directories.

- years:

  Optional years to open, 2012 or later. Defaults to every matching year
  with Parquet parts. Explicitly requested years must each have Parquet
  parts. Years before 2016 are experimental: they hold ICD-9-CM codes in
  `DX*`/`PR*` slots, and 2015 holds both systems (see
  [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)).

- reader:

  Parquet reader: `"duckdb"` (default) or `"arrow"`. Arrow is an
  optional dependency. Its reader preserves source bytes in strings,
  including malformed UTF-8, and allocates memory outside DuckDB's
  buffer limit.

- check_release:

  Check annual release totals and design fields by default. Set to
  `FALSE` to skip the check.

## Value

A lazy DuckDB-backed dbplyr table. Annual source column names are
case-normalized. Saved cohorts retain the column names used at export.

## Details

Use annual `NIS_<year>.parquet` files or directories, or Hive
directories named `YEAR=YYYY`. Use one layout per year. The package
matches columns by name and checks that recorded years agree with their
partitions. The charge fields for 2023 and 2024 remain separate from
`TOTCHG`.

## Annual release check

For years with published reference totals, the check compares
discharges, the sum of weights, and distinct hospitals when the relevant
fields are available. Investigate warnings against the annual release
documentation. Invented data and extracts created with
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)
are exempt from comparisons with published totals.

## Reading into R

Select columns and summarize in DuckDB before calling
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html).
The default reader rejects malformed UTF-8 when it reads the affected
column. Reconvert from a correctly encoded source with
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md).

## See also

[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)

## Examples

``` r
path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwxUhgt/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwxUhgt/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |>
  dplyr::count(YEAR) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
#> 2  2019    96

# Open one year only
nis_open(path, years = 2020) |>
  dplyr::count(YEAR) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwxUhgt/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 1 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
```
