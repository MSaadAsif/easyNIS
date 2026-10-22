# easyNIS

**A tidy workflow for opening, defining cohorts in, and analyzing HCUP National Inpatient Sample (NIS) data.** easyNIS opens annual Parquet files, flags codes, prepares survey designs, and helps review outputs. Methods and some year-specific support are experimental; consult the articles and official HCUP documentation before analysis.

## Install

```r
pak::pak("MSaadAsif/easyNIS")
```

## Quick start

This example runs entirely on invented `nis_example()` data.

```r
library(easyNIS)
nis <- nis_open(nis_example(years = 2019:2020))
nis <- nis |> nis_flag_dx(heart_failure = "I50")
design <- nis_design(nis, heart_failure & AGE >= 18,
                     keep = c(AGE, FEMALE, DIED, LOS), annualize = TRUE)
srvyr::summarise(design, discharges = srvyr::survey_total(),
                 mean_age = srvyr::survey_mean(AGE))
```

These results demonstrate the workflow and are not NIS population estimates.

`nis_open()` reads Parquet with DuckDB and returns a lazy dbplyr table. The
former `engine = "duckdb"` argument has been removed; omit it when updating
older code. Use `dplyr::filter()` and `dplyr::select()` before
`dplyr::collect()` to limit the data transferred into R.

## Articles

- [Get started](https://msaadasif.github.io/easyNIS/articles/getting-started.html)
- [Opening NIS data](https://msaadasif.github.io/easyNIS/articles/opening-data.html)
- [Defining cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html)
- [Survey design and weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.html)
- [Descriptives and regression](https://msaadasif.github.io/easyNIS/articles/descriptives-models.html)
- [Disclosure and suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.html)
- [Costs](https://msaadasif.github.io/easyNIS/articles/costs.html)
- [Comorbidity](https://msaadasif.github.io/easyNIS/articles/comorbidity.html)
- [Code transitions and sensitivity](https://msaadasif.github.io/easyNIS/articles/code-transitions.html)
- [Data notes by year](https://msaadasif.github.io/easyNIS/articles/year-notes.html)
- [Glossary](https://msaadasif.github.io/easyNIS/articles/glossary.html)
- [Porting a study](https://msaadasif.github.io/easyNIS/articles/porting.html) · [Background](https://msaadasif.github.io/easyNIS/articles/why-easynis.html)

Browse the [function reference](https://msaadasif.github.io/easyNIS/reference/index.html) for all exported topics.

## Citation

Run `citation("easyNIS")` in R for the package citation. Cite the HCUP NIS
documentation and other methods or code-set references used in your analysis.

## Authors and license

Muhammad Saad ([ORCID](https://orcid.org/0000-0002-1792-2357)) and Ali Salman
([ORCID](https://orcid.org/0009-0001-1102-226X)) are the package authors and
co-maintainers.
easyNIS is licensed under the [GNU Affero General Public License v3.0 only](https://github.com/MSaadAsif/easyNIS/blob/main/LICENSE).
