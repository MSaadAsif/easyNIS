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

## Articles

- [Get started](articles/getting-started.html)
- [Opening NIS data](articles/opening-data.html)
- [Defining cohorts](articles/cohorts.html)
- [Survey design and weighting](articles/survey-design.html)
- [Descriptives and regression](articles/descriptives-models.html)
- [Disclosure and suppression](articles/disclosure.html)
- [Costs](articles/costs.html)
- [Comorbidity](articles/comorbidity.html)
- [Code transitions and sensitivity](articles/code-transitions.html)
- [Data notes by year](articles/year-notes.html)
- [Glossary](articles/glossary.html)
- [Porting a study](articles/porting.html) · [Background](articles/why-easynis.html)

Browse the [function reference](reference/index.html) for all exported topics.

## Citation

Run `citation("easyNIS")` in R for the package citation. Cite the HCUP NIS
documentation and other methods or code-set references used in your analysis.
