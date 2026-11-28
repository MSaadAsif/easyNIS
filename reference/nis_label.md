# Apply HCUP labels

Apply HCUP labels

## Usage

``` r
nis_label(.data)
```

## Arguments

- .data:

  A collected data frame.

## Value

`.data` with binary indicators as logical, multi-level coded elements as
factors, and variable labels in `attr(x, "label")`. Unknown codes
trigger one warning per variable. They become `NA` in binary fields and
`Code <value>` levels in multi-level fields. Existing variable labels
are preserved. Numeric fields without a table entry are returned
unchanged. The operation is idempotent.

Residence fields `PL_NCHS2006`, `PL_NCHS`, and `PL_NCHS2` retain their
own categories. The collapsed `PL_NCHS2` uses codes 21 and 22.
Code-specific labels for `I10_BIRTH` and `I10_SERVICELINE` follow HCUP's
definitions.

Binary codes 0 and 1 become `FALSE` and `TRUE`, respectively. For
example, `FEMALE` is true for female patients and `AWEEKEND` for weekend
admissions.

Negative numeric sentinels are handled as unknown codes. The supplied
HCUP documentation represents missing numeric values as system missing
and does not document negative sentinels for any element handled here.
`NaN` values in ordinary numeric vectors and Haven-labelled numeric
storage are treated as missing, while ordinary and tagged `NA` values
remain missing. Finite SPSS user-missing values and `integer64` values
are interpreted through their displayed values. Factors containing raw
codes are normalized as a whole. Existing labels, including `Code 7`,
are preserved when unused raw-code levels remain after subsetting. A
bare `Code ` value with raw-code levels and no recognized value label is
treated as raw text; without such levels it is preserved as an existing
label because its origin cannot be recovered after dropping levels.

## See also

[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html),
[HCUP NIS Description of Data
Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_join_companion()`](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
[`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)

## Examples

``` r
demographics <- nis_open(nis_example(years = 2019)) |>
  dplyr::select(AGE, FEMALE, RACE) |>
  dplyr::collect()
head(nis_label(demographics))
#> # A tibble: 6 × 3
#>     AGE FEMALE RACE                     
#>   <dbl> <lgl>  <fct>                    
#> 1    28 TRUE   Hispanic                 
#> 2    35 FALSE  Asian or Pacific Islander
#> 3    42 TRUE   Native American          
#> 4    49 FALSE  Other                    
#> 5    56 TRUE   White                    
#> 6    63 FALSE  Black                    
```
