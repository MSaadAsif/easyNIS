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

A lazy Arrow query with case-normalized columns. Experimental 2023
layouts keep `TOTCHG_2023` as its own column and leave `TOTCHG`
untouched, because the 2023 field is HCUP-adjusted for national
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
