# Open annual NIS Parquet files lazily

Open annual NIS Parquet files lazily

## Usage

``` r
nis_open(path, years = NULL, engine = c("arrow", "duckdb"))
```

## Arguments

- path:

  Directory containing `NIS_<year>.parquet` files or directories.

- years:

  Optional years to open, 2012 or later. Defaults to every matching
  year. Years before 2016 are experimental: they hold ICD-9-CM codes in
  `DX*`/`PR*` slots, and 2015 holds both systems (see
  [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)).

- engine:

  Query engine: `"arrow"` (default) or `"duckdb"`. DuckDB queries are
  backed by Arrow's Parquet scanner and do not use DuckDB's native
  Parquet reader.

## Value

With `engine = "arrow"`, a lazy Arrow query; with `engine = "duckdb"`, a
DuckDB-backed dbplyr table. Both have case-normalized columns.
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

`engine = "duckdb"` requires the optional `duckdb` and `dbplyr`
packages. It returns a DuckDB-backed dbplyr table. The connection is
closed when the returned table is no longer referenced. The
Arrow-specific helpers
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
and
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
currently require the default Arrow engine (or a data frame where
supported). Arrow can scan a Parquet string containing invalid UTF-8
bytes, but this engine does not promise to repair them; a collected test
value retained its invalid byte.

## See also

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md).

Other data-access:
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)

## Examples

``` r
path <- nis_example(years = 2019:2020)
nis <- nis_open(path)
nis |>
  dplyr::count(YEAR) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <int>
#> 1  2020    96
#> 2  2019    96

# Open one year only
nis_open(path, years = 2020) |>
  dplyr::count(YEAR) |>
  dplyr::collect()
#> # A tibble: 1 × 2
#>    YEAR     n
#>   <int> <int>
#> 1  2020    96
```
