# Open annual NIS Parquet files lazily

Open annual NIS Parquet files lazily

## Usage

``` r
nis_open(path, years = NULL)
```

## Arguments

- path:

  Directory containing `NIS_<year>.parquet` files or directories.

- years:

  Optional years to open, 2012 or later. Defaults to every matching
  year. Years before 2016 are experimental: they hold ICD-9-CM codes in
  `DX*`/`PR*` slots, and 2015 holds both systems (see
  [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)).

## Value

A lazy DuckDB-backed dbplyr table with case-normalized columns.
Experimental 2023 layouts keep `TOTCHG_2023` as its own column and leave
`TOTCHG` untouched, because the 2023 field is HCUP-adjusted for national
estimates and is not comparable to earlier-year charges. Opening a query
that contains `TOTCHG_2023` warns once per session. To use it, pass
`charges = "TOTCHG_2023"` to
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
or
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md),
or pool explicitly with
`dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG))`.

The 2023 layout facts used here (`TOTCHG_2023`, removed `HOSP_REGION`
and `HOSP_DIVISION`, sequential `NIS_STRATUM`) are UNVERIFIED against
official HCUP 2023 documentation and real 2023 data; none were available
for testing.

## Details

`nis_open()` reads Parquet directly with DuckDB and returns a
DuckDB-backed dbplyr table. It accepts annual `NIS_<year>.parquet` files
and Hive directories named `YEAR=YYYY` containing Parquet parts. If a
part file has a physical `YEAR` column, its non-missing values must
agree with the directory year; missing or absent physical values use the
partition year. Schemas are combined by column name, including when
annual files and Hive partitions are mixed. When annual types differ,
DuckDB may promote them; for example, an integer field combined with a
character field is returned as character. When present, `YEAR` is
validated and returned as integer; invalid values identify the offending
file in an error. The connection remains open while the lazy table is in
use and closes after it is released. Use
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
to return data to R. The `engine` argument was removed entirely; omit it
regardless of the value used in older code. String columns with
malformed UTF-8 may fail during a native Parquet scan; validate or
repair those values before writing Parquet files.

## See also

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md).

Other data-access:
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)

## Examples

``` r
path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpuoupOF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpuoupOF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpuoupOF/duckdb
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
#> ℹ /tmp/RtmpuoupOF/duckdb
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
