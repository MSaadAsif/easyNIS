# Join an annual NIS companion file

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
[HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
[`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)

## Examples

``` r
nis <- nis_open(nis_example(2020))
hospitals <- dplyr::distinct(nis, HOSP_NIS, beds = HOSP_BEDSIZE)

# Write the invented Hospital part.
path <- tempfile()
dir.create(path)
con <- dbplyr::remote_con(nis)
file <- DBI::dbQuoteString(con, file.path(path, "NIS_2020.parquet"))
sql <- dbplyr::sql_render(hospitals)
invisible(DBI::dbExecute(con, paste0("COPY (", sql, ") TO ", file, " (FORMAT PARQUET)")))

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
