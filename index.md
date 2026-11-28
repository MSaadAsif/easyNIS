# easyNIS

easyNIS helps you analyze the HCUP National Inpatient Sample (NIS) in R.
Open annual files in DuckDB, define a discharge cohort with dplyr, and
use srvyr and survey to estimate totals, make tables, and fit models.

## Install

``` r

# install.packages("pak")
pak::pak("MSaadAsif/easyNIS")
```

## Usage

Estimate the total number of adult discharges with a heart failure
diagnosis across two years. This example uses invented data.

``` r

library(easyNIS)
library(dplyr)
library(srvyr)

nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_design(cohort = AGE >= 18 & heart_failure, keep = LOS) |>
  summarise(discharges = survey_total())
#> # A tibble: 1 x 2
#>   discharges discharges_se
#>        <dbl>         <dbl>
#> 1       125.          17.3
```

The output gives the weighted total and its design-based standard error.
Pass eligibility to `cohort` so the design retains the contribution of
sampled hospitals with no eligible discharges.

[Get
started](https://msaadasif.github.io/easyNIS/articles/getting-started.html)
· [Output
gallery](https://msaadasif.github.io/easyNIS/articles/gallery.html) ·
[Function
reference](https://msaadasif.github.io/easyNIS/reference/index.html)

## Using real NIS files

Keep annual Core files in a private workspace and prepare them with
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.html).
The [HCUP Data Use
Agreement](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp) prohibits
publishing cells based on 1 through 10 sampled discharges. Before
sharing statistics, also check for at least two contributing hospitals.

## Citation and license

Run `citation("easyNIS")` for the package citation. Cite the HCUP NIS
documentation and the methods and code sets used in your analysis.

easyNIS is licensed under the [GNU Affero General Public License v3.0
only](https://github.com/MSaadAsif/easyNIS/blob/main/LICENSE).
