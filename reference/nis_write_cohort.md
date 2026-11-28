# Save a reusable NIS cohort

Write cohort discharges and one zero-domain placeholder for each sampled
hospital-year without a cohort discharge. Open the resulting directory
with
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
and omit `cohort` in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
To narrow the cohort, filter the resulting survey design so its sampled
hospitals stay in scope.

## Usage

``` r
nis_write_cohort(.data, cohort, path, keep)
```

## Arguments

- .data:

  A lazy query from
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
  with any cohort flags added. Include the whole sample for the years
  you intend to analyze.

- cohort:

  Logical data-masked cohort expression. Missing values are outside the
  cohort. Omit when re-saving a dataset written by this function.

- path:

  A new output directory in an existing parent directory.

- keep:

  Tidyselect expression or character vector of analysis columns to
  write. Rename columns on the query before exporting. `YEAR`,
  `HOSP_NIS`, `NIS_STRATUM`, and `DISCWT` are always written.

## Value

The original `path`, invisibly. If collecting raw rows directly from the
saved dataset, filter on `.in_cohort` to count only discharges.

## Details

The output is a directory of yearly Zstandard-compressed Parquet parts.
Each part records the cohort expression, the years opened by the source
query, and the easyNIS version in its Parquet metadata. The expression
is recorded as supplied, so also retain the code that defines any flags
or variables it uses. The release check exempts the extract from
comparison against HCUP release totals. Saved cohorts retain the column
names used at export, including mixed-case names.

## See also

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[Defining
cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md)

## Examples

``` r
query <- nis_open(nis_example(years = 2019))
path <- nis_write_cohort(query, AGE >= 65, tempfile(), keep = LOS)
design <- nis_design(nis_open(path), keep = LOS)
dplyr::summarise(design, discharges = srvyr::survey_total())
#> # A tibble: 1 × 2
#>   discharges discharges_se
#>        <dbl>         <dbl>
#> 1       52.5          3.28
```
