# easyNIS

easyNIS is a planned R package for reproducible workflows with the HCUP National Inpatient Sample. It will help researchers import their licensed files, understand differences between years, define cohorts, estimate survey-weighted results, fit models, and produce publication tables.

**Status: planning. There are no implemented package functions or verified supported years yet.** The first private validation set is 2017–2022. The eventual coverage target is every released NIS year, currently 1988–2023. Coverage will expand through verified, staged releases.

## Start here

- [Detailed development plan](docs/PLAN.md)
- [Decisions and interview](docs/DECISIONS.md)
- [Year support matrix](docs/SUPPORT.md) and [machine-readable matrix](docs/year-support.csv)
- [Implementation backlog](docs/BACKLOG.md)
- [Evidence and references](docs/SOURCES.md)
- [Review of the existing easyNRD work](docs/EASYNRD-REVIEW.md)
- [Biostatistics workflow context](docs/CONTEXT-REVIEW.md)
- [Domain glossary](GLOSSARY.md)

## Development

Saad and Ali are developing easyNIS before resuming the broader easyNRD work. This public repository will hold development history and tagged stable releases. The new easyNIS code uses the MIT license. Reusing existing easyNRD implementation requires a separate license/permission decision.

Only invented synthetic records belong in public examples, tests, and CI. HCUP records and local reference-book copies must stay outside version control. Users obtain NIS data independently and run licensed-data checks locally.

Installation instructions will be added when an installable R package exists. Function names and examples in the plan are proposals, not an available API.

The current NIS coverage target and methodological boundaries come from [HCUP's official documentation](https://hcup-us.ahrq.gov/nisoverview.jsp). This project is independent of AHRQ/HCUP and does not imply their endorsement.
