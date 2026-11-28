# Prepare annual NIS files

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

## Convert the annual Core files

``` r

source <- nis_open(nis_example(years = 2019)) |> collect()
stata <- file.path(tempdir(), "NIS_2019_Core.dta")
haven::write_dta(source, stata)
annual <- tempfile("nis-annual-")
dir.create(annual)
nis_convert(stata, annual)
```

HCUP distributes Core files as fixed-width ASCII. Unpack the archive and
pass the annual `.asc` file to `nis_convert(path, dir)`. Use the same
private output directory for each year. In 2015, diagnosis and procedure
codes ship separately from ASCII Core. For 2015 code-based work, convert
a Stata, SAS, or SPSS file with the code slots already attached.

The example converts an invented Stata file. Stata (`.dta`), SAS
(`.sas7bdat`), and SPSS (`.sav`) inputs need `haven` and a numeric
`YEAR` column with one data year per file.

If conversion reports malformed UTF-8, check the source encoding and
correct the source or supply its known encoding for a haven format. For
example, use `encoding = "latin1"` for confirmed Latin-1 input. An
encoding override cannot repair damaged bytes.

## Open the years you need

``` r

nis <- nis_open(annual, years = 2019, check_release = FALSE)
analysis <- nis |> select(nis_vars_design(), AGE, LOS)
colnames(analysis)
#> [1] "YEAR"        "HOSP_NIS"    "NIS_STRATUM" "DISCWT"      "DQTR"       
#> [6] "AGE"         "LOS"
nis |> count(YEAR) |> collect()
#> # A tibble: 1 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2019    96
```

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
returns a DuckDB query. Keep the annual release check on when using
complete licensed releases. Compare the release-check warnings with the
annual file documentation. Use `check_release = FALSE` for an
intentional extract. Keep projection, flags, and other supported
operations before
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html). [How
easyNIS
works](https://msaadasif.github.io/easyNIS/articles/how-easynis-works.md)

## Check that your code fields can be read

``` r

nis |> count(I10_DX1, sort = TRUE) |> head(5) |> collect()
#> # A tibble: 2 × 2
#>   I10_DX1     n
#>   <chr>   <dbl>
#> 1 I5022      54
#> 2 J189       42
nis |> count(I10_PR1, sort = TRUE) |> head(5) |> collect()
#> # A tibble: 2 × 2
#>   I10_PR1     n
#>   <chr>   <dbl>
#> 1 0JH60DZ    48
#> 2 02703ZZ    48
```

A query can open before DuckDB reads text from the code fields. Check
the diagnosis and procedure columns used in your study. If one fails
with malformed UTF-8, reconvert from the correctly encoded source into a
new directory and review the release check.

Use `nis_open(reader = "arrow")` when you need to preserve malformed
source bytes. Keep only the years and columns your analysis needs.
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
collects cohort rows in R. For supported estimators,
[`nis_survey()`](https://msaadasif.github.io/easyNIS/articles/whole-sample.md)
leaves the discharge rows in DuckDB.

## Join companion files

``` r

needed <- c("HOSP_BEDSIZE", "HOSP_LOCTEACH")
missing <- setdiff(needed, colnames(nis))
missing
#> character(0)
```

If the result is empty, the requested fields are already in the opened
extract. Check their source and data years and use the existing fields.
Join only missing fields from a separate companion path.

Prepare annual companion Parquet files with their documented keys. Use
`nis_join_companion(nis, hospital_path, component = "hospital", columns = all_of(missing))`
to add hospital characteristics. Use `component = "severity"` with the
Severity file. Select only fields you need and check coverage after
joining. See the [companion join
example](https://msaadasif.github.io/easyNIS/reference/nis_join_companion.html#ref-examples)
for a complete workflow with invented data.

`TOTAL_DISC` in the Hospital file counts sampled discharges. The join
helper rejects that field. Use weighted discharge estimates for national
totals. [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)
