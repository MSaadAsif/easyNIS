# Add AHRQ Elixhauser comorbidity columns (experimental)

Reshapes the wide `I10_DX1`, `I10_DX2`, ... columns of a collected data
frame to one row per code, hands them to
[`medicalcoder::comorbidities()`](http://www.peteredewitt.com/medicalcoder/reference/comorbidities.md),
and joins the result back in the original row order. All
code-to-condition mapping and index weights come from the
[medicalcoder](https://CRAN.R-project.org/package=medicalcoder) package,
which ships the AHRQ Elixhauser Comorbidity Software Refined for
ICD-10-CM tables; easyNIS holds no clinical code lists. Install it with
`install.packages("medicalcoder")`.

## Usage

``` r
nis_comorbidity(.data, method = "elixhauser_ahrq_icd10", prefix = "cmrb_")
```

## Arguments

- .data:

  A collected data frame with `I10_DX1`, `I10_DX2`, ... columns, or a
  `tbl_svy` from
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  that kept them. Lazy Arrow queries are not accepted; call
  [`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
  first.

- method:

  A `medicalcoder` Elixhauser method name. The default,
  `"elixhauser_ahrq_icd10"`, is the union of every ICD-10 code AHRQ has
  listed since FY2022, which suits NIS years pooled across code-set
  updates. Use `"elixhauser_ahrq2022"` through `"elixhauser_ahrq2026"`
  to pin one AHRQ release.

- prefix:

  Prefix for the added columns. Existing columns are never replaced.

## Value

`.data` with one logical column per condition (`<prefix>hf`, ...),
`<prefix>n` (conditions flagged), `<prefix>any`, and the integer
`<prefix>mortality_index` and `<prefix>readmission_index` scores, using
the names and weights from `medicalcoder`. Rows with no usable `I10_DX*`
code are `NA` in all of them; see the Assumptions section.

## Details

The function is experimental: the default method and the assumptions
below remain pending scientific approval.

## Assumptions

- **Present on admission is not used.** The public NIS has no POA flags,
  so every code is passed as present on admission (`poa = 1L`).
  Conditions that AHRQ restricts to POA codes are therefore flagged
  whenever coded, which can include complications that arose during the
  stay.

- **Principal diagnosis** is `I10_DX1`. It is passed as the primary
  diagnosis, and `medicalcoder` applies the AHRQ rule for it (for
  example, a condition is not flagged from the principal diagnosis alone
  where AHRQ excludes it). Codes in `I10_DX2` onward are secondary.

- **ICD-10 only.** Only the `I10_DX*` columns are read. A discharge with
  no usable `I10_DX*` code (all blank, missing or invalid UTF-8), such
  as an ICD-9 discharge from before October 2015, gets `NA` in every
  added column, and the function warns with the number of such rows. Do
  not treat those `NA` values as "no comorbidity".

- Codes are upper-cased with periods and spaces removed. Blank, missing
  or invalid UTF-8 codes are ignored, and an unmapped code adds no
  condition. A discharge with at least one usable but unmapped code gets
  zeros.

- The long reshaping holds about 40 diagnosis columns by every row in
  memory. Use it on a cohort, not on the full national file.

## Differences from the Stata-derived columns

NIS studies often already carry `ynel*` indicators and `elixsum`,
derived in Stata from an earlier Elixhauser release. They are not
reproduced here and should not be expected to agree: the AHRQ Refined
software uses different condition definitions and categories (for
example, hypertension with and without heart failure or renal failure,
and separate liver, neurological and cancer subtypes), POA-dependent
flagging, and the principal-diagnosis rule above. Do not mix the two
sets of indicators in one model.

## Use with [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
needs the whole hospital-year frame to build placeholder rows, so do not
collect and enrich the cohort before calling it. Keep the diagnosis
columns in the design instead, then pass the design here:

    design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX")))
    design <- nis_comorbidity(design)

For a `tbl_svy` the function replaces `design$variables` and leaves the
design (clusters, strata, weights) untouched.

## Examples

``` r
# \donttest{
if (rlang::is_installed("medicalcoder", version = "0.10.0")) {
  discharges <- nis_open(nis_example(years = 2019)) |>
    dplyr::select(AGE, dplyr::starts_with("I10_DX")) |>
    dplyr::collect()
  comorbid <- nis_comorbidity(discharges)
  comorbid[c("AGE", "cmrb_n", "cmrb_any")] |> head()
}
#> # A tibble: 6 × 3
#>     AGE cmrb_n cmrb_any
#>   <dbl>  <int> <lgl>   
#> 1    28      1 TRUE    
#> 2    35      1 TRUE    
#> 3    42      1 TRUE    
#> 4    49      0 FALSE   
#> 5    56      1 TRUE    
#> 6    63      1 TRUE    
# }
```
