# Convert a NIS file to annual Parquet

Convert one annual Core file into Parquet.

## Usage

``` r
nis_convert(path, dir, encoding = NULL)
```

## Arguments

- path:

  Path to one annual NIS Stata (`.dta`), SAS (`.sas7bdat`), or SPSS
  (`.sav`) file with a numeric `YEAR` column, or one HCUP fixed-width
  `NIS_<year>_Core.ASC` file from 2012 through 2024.

- dir:

  Existing directory in which to create `NIS_<year>.parquet/`.

- encoding:

  Source encoding override passed to haven. The default uses the
  reader's format-specific encoding. Use `"latin1"` for a legacy Stata
  file known to use Latin-1.

## Value

The path of the annual Parquet directory, invisibly.

## Details

The converter accepts HCUP's fixed-width Core layout for 2012 through
2024 and annual Stata, SAS, or SPSS files. For those three formats,
supply a numeric `YEAR` column. All rows must have the same year.
Populated code slots must agree with the coding era. The 2015 ASCII Core
file has separate diagnosis and procedure files that this function does
not join.

Conversion stops on malformed text or invalid codes. Use an existing
output directory. The converter creates one new annual directory and
leaves any existing annual directory intact.

## See also

[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html)

Other data-access:
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
[`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)

## Examples

``` r
if (requireNamespace("haven", quietly = TRUE)) {
  dir <- tempfile()
  dir.create(dir)
  path <- file.path(dir, "NIS_2020.dta")
  nis <- nis_open(nis_example(2020)) |>
    dplyr::select(YEAR, KEY_NIS, I10_DX1) |>
    dplyr::collect()
  haven::write_dta(nis, path)
  nis_convert(path, dir)
  nis_open(dir, check_release = FALSE) |>
    dplyr::count(YEAR) |>
    dplyr::collect()
}
#> # A tibble: 1 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
```
