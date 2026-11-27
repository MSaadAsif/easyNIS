# easyNIS

[![R-CMD-check](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/MSaadAsif/easyNIS/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/pkgdown.yaml)
[![Test coverage
workflow](https://github.com/MSaadAsif/easyNIS/actions/workflows/test-coverage.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/test-coverage.yaml)
[![Project Status:
WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)
[![Lifecycle:
experimental](https://lifecycle.r-lib.org/articles/figures/lifecycle-experimental.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)

easyNIS opens annual HCUP National Inpatient Sample (NIS) files and
helps you define discharge cohorts. Use it to estimate national totals,
fit survey-weighted models, and review results for disclosure.

## Install

``` r

pak::pak("MSaadAsif/easyNIS")
```

## Estimate a cohort total

This example uses invented data.

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
design <- nis_design(nis, cohort = AGE >= 18 & heart_failure, keep = LOS)
filtered <- nis_design(filter(nis, AGE >= 18, heart_failure), cohort = TRUE, keep = LOS)
bind_rows(cohort = summarise(design, discharges = survey_total()),
          prefiltered = summarise(filtered, discharges = survey_total()), .id = "design")
```

Both designs estimate the same weighted total. Their standard errors
differ. Pass eligibility to `cohort` to account for every sampled
hospital. [See the two calculations side by
side](https://msaadasif.github.io/easyNIS/articles/how-easynis-works.html#define-the-domain-after-identifying-the-sample).

## Using real NIS files

Unpack each annual Core file and convert it with
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.html).
Open the Parquet directory with
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).
Keep the files in your private workspace. The [HCUP Data Use
Agreement](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp) prohibits
publishing cells based on 1 through 10 discharges.

[Get
started](https://msaadasif.github.io/easyNIS/articles/getting-started.html)
·
[Guides](https://msaadasif.github.io/easyNIS/articles/index.html#guides)
·
[Concepts](https://msaadasif.github.io/easyNIS/articles/index.html#concepts)

## Citation

Run `citation("easyNIS")` in R for the package citation. Cite the HCUP
NIS documentation and other methods or code-set references used in your
analysis.

## Authors and license

Muhammad Saad ([ORCID](https://orcid.org/0000-0002-1792-2357)) and Ali
Salman ([ORCID](https://orcid.org/0009-0001-1102-226X)) are the package
authors and co-maintainers. easyNIS is licensed under the [GNU Affero
General Public License v3.0
only](https://github.com/MSaadAsif/easyNIS/blob/main/LICENSE).
