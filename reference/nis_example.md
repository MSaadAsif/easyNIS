# Create invented NIS Parquet files

Create invented NIS Parquet files

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

[Analyze your first NIS
cohort](https://msaadasif.github.io/easyNIS/articles/getting-started.html).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
[`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)

## Examples

``` r
path <- nis_example(years = 2019:2020)
list.files(path)
#> [1] "NIS_2019.parquet" "NIS_2020.parquet"
```
