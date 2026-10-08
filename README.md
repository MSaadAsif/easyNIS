# easyNIS

easyNIS is an R package in early development for reproducible workflows with the HCUP National Inpatient Sample. The planned workflow covers importing licensed files, annual differences, cohorts, survey-weighted results, models, and publication tables.

**Status: experimental structural import and user-declared code matching implemented. No licensed-data years are release-supported yet.** The development package provides a capability roadmap, entirely invented fixtures, lazy parquet inspection, aggregate structural checks, and code flags with explicit scope and missingness policies. Annual adapters and statistical analysis remain unimplemented. The first private validation set is 2017–2022. The recorded coverage roadmap is 1988–2023 and will expand through verified, staged releases.

## Install and try the development package

Install the runtime dependencies in R with `install.packages(c("DBI", "duckdb"))`.
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

The current functions are `nis_supported_years()`, `nis_synthetic_data()`,
`nis_open()`, `nis_close()`, `nis_import()`, `nis_collect()`, `nis_validate()`,
`nis_code_set()`, `nis_flag_codes()`, `nis_select()`, `nis_survey_design()`, and
`nis_domain()`.
The import API is experimental. Use `example(nis_import)` for an offline
parquet demonstration. Structural checks preserve raw values and always report
`analysis_ready = FALSE`. The full analysis example in the plan remains a
proposal, not an executable API.

Code matching requires a user-declared code set with system, valid years,
version, source, and author. Flags retain all discharges and record selected
slots. Clinical validity and annual code dictionaries remain unverified. Run
`example(nis_flag_codes)` offline and read the [matcher contract](docs/COHORTS.md).

`nis_select()` narrows a lazy relation without filtering records. Validation
can report columns removed by selection separately from unverified source or
conversion absences. Explicit field requests return SQL NULL counts without
interpreting special missing-value sentinels. Run `example(nis_select)` offline.

Experimental `nis_survey_design()` collects a narrow full-population projection
for a native `survey` design. `nis_domain()` selects logical domains after
construction. Population, method, singleton and domain missingness declarations
are explicit. Read the [experimental design contract](docs/SURVEY.md) and run
`example(nis_survey_design)` offline. Annual inference approval remains pending.

The current NIS coverage target and methodological boundaries come from [HCUP's official documentation](https://hcup-us.ahrq.gov/nisoverview.jsp). This project is independent of AHRQ/HCUP and does not imply their endorsement.
