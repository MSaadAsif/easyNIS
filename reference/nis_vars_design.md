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
[Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.html),
[HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp),
[HCUP NIS Description of Data
Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp).

## Examples

``` r
nis <- nis_open(nis_example(years = 2019))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpCHalTi/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpCHalTi/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
dplyr::select(nis, nis_vars_design(), nis_vars_demographics(), LOS)
#> # A query:  ?? x 13
#> # Database: DuckDB 2.0.1 [unknown@Linux 7.0.0-1020-azure:R 4.6.2/:memory:]
#>     YEAR HOSP_NIS NIS_STRATUM DISCWT  DQTR   AGE AGE_NEONATE FEMALE  RACE  PAY1
#>    <int>    <int>       <int>  <dbl> <int> <dbl>       <int>  <int> <int> <int>
#>  1  2019        1           1    1.1     1    28           0      1     3     3
#>  2  2019        1           1    1.1     2    35           0      0     4     4
#>  3  2019        1           1    1.1     3    42           0      1     5     5
#>  4  2019        1           1    1.1     4    49           0      0     6     6
#>  5  2019        1           1    1.1     1    56           0      1     1     1
#>  6  2019        1           1    1.1     2    63           0      0     2     2
#>  7  2019        1           1    1.1     3    70           0      1     3     3
#>  8  2019        1           1    1.1     4    77           0      0     4     4
#>  9  2019        2           1    1.2     1    31           0      0     4     4
#> 10  2019        2           1    1.2     2    38           0      1     5     5
#> # ℹ more rows
#> # ℹ 3 more variables: ZIPINC_QRTL <int>, PL_NCHS <int>, LOS <dbl>
dplyr::select(nis, c(nis_vars_dx(), nis_vars_pr()))
#> # A query:  ?? x 67
#> # Database: DuckDB 2.0.1 [unknown@Linux 7.0.0-1020-azure:R 4.6.2/:memory:]
#>    I10_DX1 I10_DX10 I10_DX11 I10_DX12 I10_DX13 I10_DX14 I10_DX15 I10_DX16
#>    <chr>   <chr>    <chr>    <chr>    <chr>    <chr>    <chr>    <chr>   
#>  1 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  2 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  3 J189    NA       NA       NA       NA       NA       NA       NA      
#>  4 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  5 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  6 J189    NA       NA       NA       NA       NA       NA       NA      
#>  7 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  8 I5022   NA       NA       NA       NA       NA       NA       NA      
#>  9 I5022   NA       NA       NA       NA       NA       NA       NA      
#> 10 I5022   NA       NA       NA       NA       NA       NA       NA      
#> # ℹ more rows
#> # ℹ 59 more variables: I10_DX17 <chr>, I10_DX18 <chr>, I10_DX19 <chr>,
#> #   I10_DX2 <chr>, I10_DX20 <chr>, I10_DX21 <chr>, I10_DX22 <chr>,
#> #   I10_DX23 <chr>, I10_DX24 <chr>, I10_DX25 <chr>, I10_DX26 <chr>,
#> #   I10_DX27 <chr>, I10_DX28 <chr>, I10_DX29 <chr>, I10_DX3 <chr>,
#> #   I10_DX30 <chr>, I10_DX31 <chr>, I10_DX32 <chr>, I10_DX33 <chr>,
#> #   I10_DX34 <chr>, I10_DX35 <chr>, I10_DX36 <chr>, I10_DX37 <chr>, …
dplyr::select(nis, -nis_vars_pr())
#> # A query:  ?? x 83
#> # Database: DuckDB 2.0.1 [unknown@Linux 7.0.0-1020-azure:R 4.6.2/:memory:]
#>      AGE AGE_NEONATE AMONTH APRDRG_RISK_MORTALITY APRDRG_SEVERITY AWEEKEND
#>    <dbl>       <int>  <int>                 <int>           <int>    <int>
#>  1    28           0      3                     2               3        0
#>  2    35           0      4                     3               4        0
#>  3    42           0      5                     4               0        0
#>  4    49           0      6                     0               1        0
#>  5    56           0      7                     1               2        0
#>  6    63           0      8                     2               3        1
#>  7    70           0      9                     3               4        1
#>  8    77           0     10                     4               0        0
#>  9    31           0      4                     3               4        0
#> 10    38           0      5                     4               0        0
#> # ℹ more rows
#> # ℹ 77 more variables: CCR_NIS <dbl>, DIED <int>, DISCWT <dbl>,
#> #   DISPUNIFORM <dbl>, DQTR <int>, DRG_NOPOA <int>, ELECTIVE <int>,
#> #   FEMALE <int>, HCUP_ED <int>, HOSP_BEDSIZE <int>, HOSP_DIVISION <int>,
#> #   HOSP_LOCTEACH <int>, HOSP_NIS <int>, HOSP_REGION <int>, H_CONTRL <int>,
#> #   I10_BIRTH <int>, I10_DELIVERY <int>, I10_DX1 <chr>, I10_DX10 <chr>,
#> #   I10_DX11 <chr>, I10_DX12 <chr>, I10_DX13 <chr>, I10_DX14 <chr>, …
```
