# ICD-10 codes in HCUP CCSR categories

Reads the official HCUP DXCCSR or PRCCSR reference file that you
download yourself and returns the full ICD-10-CM or ICD-10-PCS codes
assigned to the requested categories. Pass the result to
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
or
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
which treat each code as a prefix. easyNIS does not ship or download any
CCSR content, and the code lists depend on the reference file version
you supply.

## Usage

``` r
nis_ccsr_codes(file, categories, default_only = FALSE)
```

## Arguments

- file:

  Path to the HCUP CCSR reference file.

- categories:

  Character vector of CCSR category codes, such as `"CIR019"`. Matching
  ignores case.

- default_only:

  If `TRUE`, keep only codes whose default inpatient category is in
  `categories`. Diagnosis reference files only.

## Value

A sorted character vector of unique codes without periods.

## Details

The reference file may be the HCUP Excel workbook (`.xlsx`, which needs
the readxl package) or the HCUP comma-separated file. Excel files are
read from the `DX_to_CCSR_Mapping` or `PR_to_CCSR_Mapping` sheet.
Comma-separated files use the wide layout with `CCSR CATEGORY 1`,
`CCSR CATEGORY 2`, and so on. A code mapped to a category in any of
those columns is returned.

With `default_only = TRUE`, only codes whose default inpatient CCSR
category is one of `categories` are returned. This matches the HCUP
assignment of a single category to a principal diagnosis, so combine it
with `position = "principal"` in
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md).
Procedure reference files have no default assignment.

UNVERIFIED: the file layouts above are assumed from secondhand
descriptions of HCUP downloads, not checked against a current release.
The single-quoted CSV reader checks row field counts; all supported
formats check that codes look like ICD-10 codes (3 to 7 letters or
digits). Check the returned codes against your reference file before you
rely on them.

This function is experimental.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx_position.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

## Examples

``` r
# An invented reference file in the HCUP comma-separated layout. Download
# the real DXCCSR file from HCUP and pass its path instead.
reference <- tempfile(fileext = ".csv")
writeLines(c(
  "'ICD-10-CM CODE','CCSR CATEGORY 1','CCSR CATEGORY 2','DEFAULT CCSR CATEGORY IP'",
  "'I5022','CIR019','','CIR019'",
  "'I509','CIR019','','CIR019'",
  "'E119','END002','','END002'"
), reference)
codes <- nis_ccsr_codes(reference, "CIR019")
codes
#> [1] "I5022" "I509" 

nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = codes) |>
  dplyr::count(heart_failure) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpe41Z1U/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpe41Z1U/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 2 × 2
#>   heart_failure     n
#>   <lgl>         <dbl>
#> 1 FALSE            42
#> 2 TRUE             54
```
