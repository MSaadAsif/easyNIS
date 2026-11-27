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

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md),
[HCUP NIS Description of Data
Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).

Other data-access:
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md),
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)

## Examples

``` r
demographics <- nis_open(nis_example(years = 2019)) |>
  dplyr::select(AGE, FEMALE, RACE) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpWkWQQQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpWkWQQQ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
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
