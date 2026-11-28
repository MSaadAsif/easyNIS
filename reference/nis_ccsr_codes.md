# Find ICD-10 codes in a CCSR category

Returns the full ICD-10-CM or ICD-10-PCS codes assigned to the requested
categories in a bundled AHRQ HCUP CCSR release. Use
[`nis_add_ccsr()`](https://msaadasif.github.io/easyNIS/reference/nis_add_ccsr.md)
for exact, year-aware matching on a lazy NIS query.

## Usage

``` r
nis_ccsr_codes(
  categories,
  file = NULL,
  default_only = FALSE,
  type = c("dx", "pr"),
  version = NULL
)
```

## Arguments

- categories:

  Character vector of CCSR category codes, such as `"CIR019"`. Matching
  ignores case.

- file:

  Optional path to an HCUP reference file for a custom or newer release.
  The file determines whether the mapping is for diagnoses or
  procedures.

- default_only:

  If `TRUE`, keep only codes whose default inpatient category is in
  `categories`. Diagnosis reference files only.

- type:

  `"dx"` for diagnosis or `"pr"` for procedure lookups in the bundled
  data.

- version:

  A bundled version, such as `"2025.1"`. The default is the latest
  bundled release of the requested `type`.

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
with an exact match on the principal diagnosis code. Procedure reference
files have no default assignment.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_audit_dx_position()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_dx_position.md),
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)

## Examples

``` r
head(nis_ccsr_codes("CIR019"))
#> [1] "I0981" "I110"  "I130"  "I132"  "I501"  "I5020"
```
