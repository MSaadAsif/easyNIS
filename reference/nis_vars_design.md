# Select NIS column groups

Use these helpers inside
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html)
and easyNIS tidy-select arguments, such as `keep` in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
or `columns` in
[`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md).
Groups use HCUP field names from 2012 onward. Each helper selects the
columns present in the input. Combine groups with
[`c()`](https://rdrr.io/r/base/c.html) or exclude them with `-`.

## Usage

``` r
nis_vars_design()

nis_vars_demographics()

nis_vars_dx()

nis_vars_pr()

nis_vars_hospital()
```

## Value

Tidyselect column positions for the current selection.

## Details

- `nis_vars_design()` selects `YEAR`, `HOSP_NIS`, `NIS_STRATUM`,
  `DISCWT`, and `DQTR` when available. Include it when projecting a
  table before building a design.
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  checks the four required fields and errors if any are missing. `DQTR`
  supports 2015 coverage checks.

- `nis_vars_demographics()` selects age, neonatal age indicator, sex,
  race, expected primary payer, ZIP income quartile, and the applicable
  urban-rural field.

- `nis_vars_dx()` selects numbered ICD-9 and ICD-10 diagnosis, external
  cause, and present-on-admission fields, plus diagnosis counts and
  `DXVER` when present.

- `nis_vars_pr()` selects numbered ICD-9 and ICD-10 procedure and
  procedure-day fields, plus procedure counts and `PRVER` when present.

- `nis_vars_hospital()` selects the hospital identifier and bed size,
  ownership, location/teaching, region, and division fields.
  Availability depends on the release and whether the Hospital file was
  joined.

These helpers match names and do not check how the fields were coded.
Diagnosis and procedure groups do not include derived classification
fields such as CCS or CCSR.

## See also

[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html),
[HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp),
[HCUP NIS Description of Data
Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019))
analysis <- dplyr::select(nis, nis_vars_design(), AGE, LOS)
names(analysis)
#> ! The `names()` method of <tbl_lazy> is for internal use only.
#> ℹ Did you mean `colnames()`?
#> [1] "con"        "src"        "lazy_query"
code_columns <- dplyr::select(nis, nis_vars_dx(), nis_vars_pr())
head(names(code_columns))
#> ! The `names()` method of <tbl_lazy> is for internal use only.
#> ℹ Did you mean `colnames()`?
#> [1] "con"        "src"        "lazy_query"
```
