# Write an invented NIS-shaped Parquet dataset

Write an invented NIS-shaped Parquet dataset

## Usage

``` r
nis_example(years = 2017:2022)
```

## Arguments

- years:

  Years to create, from 2012 through 2024. Years before 2016 are
  experimental. The 2015 fixture has separate ICD-9 and ICD-10 slots,
  with invented codes and version indicators; it is not a clinical
  crosswalk.

## Value

The temporary directory containing `NIS_<year>.parquet/` entries.

## See also

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md).

Other data-access:
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)

## Examples

``` r
path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzwSW2n/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzwSW2n/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
list.files(path)
#> [1] "NIS_2019.parquet" "NIS_2020.parquet"
```
