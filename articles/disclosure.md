# Check disclosure before sharing results

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

## Count the discharges and hospitals behind each cell

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwDMKrz/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwDMKrz/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
counts <- nis_cell_counts(nis, by = c(YEAR, heart_failure))
counts
#> # A tibble: 4 × 4
#>    YEAR heart_failure     n hospitals
#>   <int> <lgl>         <dbl>     <dbl>
#> 1  2019 FALSE            42        12
#> 2  2019 TRUE             54         9
#> 3  2020 FALSE            42        12
#> 4  2020 TRUE             54         9
```

The HCUP Data Use Agreement prohibits publishing cells based on 1
through 10 sampled discharges and prohibits publishing identifying
information. easyNIS also masks statistics supported by fewer than two
hospitals. Check support for the records contributing to each statistic.
[HCUP Data Use
Agreement](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp)

## Mask a summary and check what can be recovered

``` r

groups <- nis |>
  mutate(age_group = if_else(AGE >= 87, "87 and older", "under 87"))
cells <- nis_cell_counts(groups, by = c(YEAR, age_group))
cells |>
  nis_suppress(count_col = n, hospital_col = hospitals,
               by = YEAR, secondary = TRUE)
#> # A tibble: 4 × 4
#>    YEAR age_group    n      hospitals
#>   <int> <chr>        <chr>  <chr>    
#> 1  2019 87 and older ≤10    ≤10      
#> 2  2019 under 87     Masked Masked   
#> 3  2020 87 and older ≤10    ≤10      
#> 4  2020 under 87     Masked Masked
```

If the year total is public, a reader can subtract the published age
group to recover the masked group. Complementary suppression hides
another value to prevent that deduction. The data-frame helper can mask
the smallest remaining positive cell when a group has one primary mask.
Keep totals out of that input and decide which totals can be released.
The helper also masks zeros as a conservative default.

## Mask a survey table

Install `gtsummary` and `cardx` to run the survey table examples.

``` r

library(gtsummary)

design <- nis_design(nis, AGE >= 18, keep = c(AGE, RACE, heart_failure))
#> Preparing the cohort survey design.
tbl_svysummary(design, by = heart_failure, include = c(AGE, RACE)) |>
  nis_suppress()
```

[TABLE]

The helper checks the non-missing complement of a displayed two-level
indicator and masks related overall statistics when a group is masked.
If exactly one level of a categorical variable is masked in a column,
the helper also masks the smallest remaining positive level in that
column. Check whether percentages, totals, or other outputs reveal a
masked cell before release.

## Export a three-group table to CSV

The oldest age group in this invented example has ten or fewer sampled
discharges.
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
masks its header denominator and its statistics.
[`as_tibble()`](https://tibble.tidyverse.org/reference/as_tibble.html)
carries the masked heading into the CSV. Use `<=` for the
less-than-or-equal suppression marker so the file also works in
non-UTF-8 locales.

``` r

bands <- nis |>
  mutate(age_group = case_when(
    AGE >= 90 ~ "90 and older",
    AGE >= 65 ~ "65 to 89",
    AGE >= 18 ~ "18 to 64"
  ))
age_design <- nis_design(bands, cohort = AGE >= 18, keep = c(age_group, LOS))
#> Preparing the cohort survey design.
masked <- tbl_svysummary(age_design, by = age_group, include = LOS) |>
  nis_suppress()
csv <- tibble::as_tibble(masked) |>
  mutate(across(-1L, ~ sub("\u2264", "<=", .x, fixed = TRUE)))
file <- tempfile(fileext = ".csv")
write.csv(csv, file, row.names = FALSE)
read.csv(file, check.names = FALSE)
#>     **Characteristic** **18 to 64**  \nN = 124 **65 to 89**  \nN = 98
#> 1 Length of stay, days          6.0 (5.0, 8.0)         3.0 (1.0, 9.0)
#>   **90 and older**  \nN = Masked
#> 1                           <=10
```

Review the CSV alongside any table headings, footnotes, totals, and
related outputs you plan to share.
