# easyNIS

[![R-CMD-check](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/MSaadAsif/easyNIS/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/pkgdown.yaml)

**A tidy workflow for opening, defining cohorts in, and analyzing HCUP
National Inpatient Sample (NIS) data.** easyNIS opens annual Parquet
files, flags codes, prepares survey designs, and helps review outputs.
Methods and some year-specific support are experimental; consult the
articles and official HCUP documentation before analysis.

## Install

``` r

pak::pak("MSaadAsif/easyNIS")
```

This installs the development version from GitHub.

## Quick start

This example runs entirely on invented
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
data.

``` r

library(easyNIS)
nis <- nis_open(nis_example(years = 2019:2020))
nis <- nis |> nis_flag_dx(heart_failure = "I50")
design <- nis_design(nis, heart_failure & AGE >= 18,
                     keep = c(AGE, FEMALE, DIED, LOS), annualize = TRUE)
srvyr::summarise(design, discharges = srvyr::survey_total(),
                 mean_age = srvyr::survey_mean(AGE))
```

These results demonstrate the workflow and are not NIS population
estimates.

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
reads Parquet with DuckDB and returns a lazy dbplyr table. Use
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
and
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html)
before
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
to limit the data transferred into R.

## Using real NIS data

easyNIS does not bundle or download NIS data. HCUP distributes
fixed-width ASCII files with SAS, Stata, and SPSS load programs; see the
[Data Use Agreement](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp)
and [Checklist for Working with the
NIS](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp).
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
accepts a directory containing `NIS_YYYY.parquet` files or `YEAR=YYYY`
subdirectories; convert HCUP files to Parquet first. The HCUP Nationwide
Data Use Agreement advises avoiding publication of values of 1–10 in
text and tables. The checklist says at least two hospitals must
contribute to each cell.
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
masks counts at or below `threshold` (10 by default), applies
complementary suppression by default for data frames, and, when given
hospital counts from
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md),
masks cells from fewer than two hospitals. Try with invented
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
data before using licensed files.

## Articles

- [Get
  started](https://msaadasif.github.io/easyNIS/articles/getting-started.html)
- [Opening NIS
  data](https://msaadasif.github.io/easyNIS/articles/opening-data.html)
- [Defining
  cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html)
- [Survey design and
  weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.html)
- [Descriptives and
  regression](https://msaadasif.github.io/easyNIS/articles/descriptives-models.html)
- [Disclosure and
  suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.html)
- [Costs](https://msaadasif.github.io/easyNIS/articles/costs.html)
- [Comorbidity](https://msaadasif.github.io/easyNIS/articles/comorbidity.html)
- [Code transitions and
  sensitivity](https://msaadasif.github.io/easyNIS/articles/code-transitions.html)
- [Data notes by
  year](https://msaadasif.github.io/easyNIS/articles/year-notes.html)
- [Glossary](https://msaadasif.github.io/easyNIS/articles/glossary.html)
- [Porting a
  study](https://msaadasif.github.io/easyNIS/articles/porting.html) ·
  [Background](https://msaadasif.github.io/easyNIS/articles/why-easynis.html)

Browse the [function
reference](https://msaadasif.github.io/easyNIS/reference/index.html) for
all exported topics.

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
