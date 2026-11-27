# How easyNIS works

``` r

library(easyNIS)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
library(srvyr)
#> 
#> Attaching package: 'srvyr'
#> The following object is masked from 'package:stats':
#> 
#>     filter

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpMivO46/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpMivO46/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```

The examples use invented data. `nis` is a query over Parquet files.
DuckDB reads the columns needed when you ask for a result.

| Task | Where the work happens |
|----|----|
| [`select()`](https://dplyr.tidyverse.org/reference/select.html), [`filter()`](https://dplyr.tidyverse.org/reference/filter.html), code flags, and derived outcomes on an open query | Add steps to the DuckDB query. |
| [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md), coding audits, [`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md), and supported [`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md) summaries | Aggregate in DuckDB and return the result to R. |
| [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md) | Collect the cohort columns and sampled hospital structure needed for an R survey design. |
| [`collect()`](https://dplyr.tidyverse.org/reference/compute.html) | Bring the rows and columns in the query into R. |
| [`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md) on a data frame or survey table | Work on an object already in R. |

## Define the domain after identifying the sample

A cohort is the set of discharges that meet your study criteria. A
survey domain is the subpopulation you estimate within the original
sample design. In the next example, both designs estimate the same
cohort total. Filtering the input first changes the standard error here
and can change the design degrees of freedom. In this example both
designs have 12 degrees of freedom.

``` r

domain <- nis_design(nis, cohort = heart_failure, keep = AGE)
#> Preparing the cohort survey design.
filtered <- nis_design(filter(nis, heart_failure), cohort = TRUE, keep = AGE)
#> Preparing the cohort survey design.
bind_rows(full_sample = summarise(domain, total = survey_total()),
          prefiltered = summarise(filtered, total = survey_total()), .id = "design")
#> # A tibble: 2 × 3
#>   design      total total_se
#>   <chr>       <dbl>    <dbl>
#> 1 full_sample  125.    17.3 
#> 2 prefiltered  125.     3.70
c(full_sample = survey::degf(domain), prefiltered = survey::degf(filtered))
#> full_sample prefiltered 
#>          12          12
```

[`filter()`](https://dplyr.tidyverse.org/reference/filter.html) on the
open query removes discharges before the design is defined. Pass
eligibility to `nis_design(cohort = )` or use
[`filter()`](https://dplyr.tidyverse.org/reference/filter.html) on an
existing
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
or
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
object to define a domain within the sample. Hospital-years with no
eligible cases still contribute zero to the variance calculation. See
[How the NIS survey design
works](https://msaadasif.github.io/easyNIS/articles/nis-design.md).

## Choose a survey object

| Your analysis | Use |
|----|----|
| A cohort fits in R and you want srvyr, survey, or gtsummary methods. | [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md) |
| You need to analyze many discharges and your summary or model has a DuckDB-backed method. | [`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md) |

## Decide how to pool years

The original discharge weights estimate totals across the included
years. `annualize = TRUE` divides every weight by the number of included
design years. This rescales a pooled total to an average per included
year and leaves means, proportions, and odds ratios unchanged. Each
partial year counts as one year. See [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)
for coverage checks.

## Document how you handle singleton strata

A lonely primary sampling unit (PSU) is the sole sampled hospital in a
stratum. `survey.lonely.psu` sets the variance policy for those strata.
`survey.adjust.domain.lonely` controls adjustments for a single
contributing hospital in a domain within a stratum that has multiple
sampled hospitals. Choose and report the settings used in your study.
