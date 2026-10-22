# Apply HCUP labels

Apply HCUP labels

## Usage

``` r
nis_label(data)
```

## Arguments

- data:

  A collected data frame.

## Value

`data` with known coded elements as factors and variable labels in
`attr(x, "label")`. Unknown codes are retained as `Code <value>` levels
with one warning per variable. Existing labels and labelled comorbidity
fields are preserved. Elements without a table entry, including the 2023
`PL_NCHS2` and `TOTCHG_2023` fields, are returned unchanged. The
operation is idempotent.

Negative numeric sentinels are not converted to missing values. The
supplied HCUP documentation represents missing numeric values as system
missing and does not document negative sentinels for any element handled
here.

## See also

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md).

Other data-access:
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)

## Examples

``` r
demographics <- nis_open(nis_example(years = 2019)) |>
  dplyr::select(AGE, FEMALE, RACE) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpuoupOF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpuoupOF/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
head(nis_label(demographics))
#> # A tibble: 6 × 3
#>     AGE FEMALE RACE                     
#>   <dbl> <fct>  <fct>                    
#> 1    28 Female Hispanic                 
#> 2    35 Male   Asian or Pacific Islander
#> 3    42 Female Native American          
#> 4    49 Male   Other                    
#> 5    56 Female White                    
#> 6    63 Male   Black                    
```
