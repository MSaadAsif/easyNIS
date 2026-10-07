# easyNIS

easyNIS is an R package in early development for reproducible workflows with the HCUP National Inpatient Sample. The planned workflow covers importing licensed files, annual differences, cohorts, survey-weighted results, models, and publication tables.

**Status: package foundation implemented. No licensed-data years are supported yet.** The development package provides a capability roadmap and entirely invented fixtures. Import and statistical analysis remain unimplemented. The first private validation set is 2017–2022. The recorded coverage roadmap is 1988–2023 and will expand through verified, staged releases.

## Install and try the development package

From a local checkout, run `R CMD INSTALL .` in a terminal. This package is not
on CRAN. In R:

```r
library(easyNIS)

nis_supported_years(2017:2022)
nis_supported_years(supported_only = TRUE) # No supported years yet.

fixture <- nis_synthetic_data(2022)
head(fixture$core)
sum(fixture$core$DISCWT) # 36 invented weighted discharges.
fixture$expected$age_mean_observed # 42.5; arithmetic, not survey inference.
```

The fixture's slots and components are test choices, not verified annual layouts.
The examples run offline and do not read licensed files. Read the
[fixture contract](inst/extdata/synthetic/README.md) and
[contribution guide](CONTRIBUTING.md) for development checks.

## Start here

- [Detailed development plan](docs/PLAN.md)
- [Decisions and interview](docs/DECISIONS.md)
- [Year support matrix](docs/SUPPORT.md) and [machine-readable matrix](inst/metadata/year-support.csv)
- [Implementation backlog](docs/BACKLOG.md)
- [Evidence and references](docs/SOURCES.md)
- [Review of the existing easyNRD work](docs/EASYNRD-REVIEW.md)
- [Biostatistics workflow context](docs/CONTEXT-REVIEW.md)
- [Domain glossary](GLOSSARY.md)

## Development

Saad and Ali are developing easyNIS before resuming the broader easyNRD work. This public repository will hold development history and tagged stable releases. The new easyNIS code uses the MIT license. Reusing existing easyNRD implementation requires a separate license/permission decision.

Only invented synthetic records belong in public examples, tests, and CI. HCUP records and local reference-book copies must stay outside version control. Users obtain NIS data independently and run licensed-data checks locally.

Only `nis_supported_years()` and `nis_synthetic_data()` are available now. The
full analysis example in the plan remains a proposal, not an executable API.

The current NIS coverage target and methodological boundaries come from [HCUP's official documentation](https://hcup-us.ahrq.gov/nisoverview.jsp). This project is independent of AHRQ/HCUP and does not imply their endorsement.
