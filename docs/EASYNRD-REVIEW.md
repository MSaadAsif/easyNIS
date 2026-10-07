# Review of existing easyNRD work

Read-only review on 2026-10-08 of AliSalman-et-al/easyNRD and MSaadAsif/easyNRD-public. Both `master` branches were identical at commit `82a55a96a82e1302828b60bad766226b883af101`. GitHub confirms the public repository is a fork of Ali's repository, with no commits ahead or behind at review time. This is a static audit, not a claim that the test suite was run.

## Implemented work

| Area | Observed capability | Evidence at inspected commit |
|---|---|---|
| Package | Development version 0.0.0.9015, R >= 4.2, declared dependencies. | [DESCRIPTION](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/DESCRIPTION) |
| Import/storage | Parquet/Arrow to DuckDB; name normalization; managed resources. | [R/ingest.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/ingest.R) |
| Cohorts | ICD-10 exact/regex matching with diagnosis scopes and SQL execution. | [R/phenotype.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/phenotype.R) |
| NRD linkage | Timing preparation and first qualifying within-year readmission linkage. | [R/prepare.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/prepare.R), [R/link_readmissions.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/link_readmissions.R) |
| Annual pipeline | Per-year work, parquet export, and re-ingested row union. | [R/pipeline.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/pipeline.R) |
| Analysis helpers | Labels/factors, survey wrapper, schema/query diagnostics, checkpoints, cleanup. | [R/survey.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/R/survey.R) and other R modules. |
| Documentation/tests | Function help, six vignettes, synthetic integration and survey-reference tests. | [tests/testthat/test-integration.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/tests/testthat/test-integration.R), [tests/testthat/test-survey.R](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/tests/testthat/test-survey.R) |

## Gaps relevant to easyNIS planning

The stated scope is 2016 onward. There is no verified all-year registry, ICD-9/2015 support, or raw HCUP fixed-width importer. Preparing an existing parquet file is different from loading an original release. Static labels and hardcoded diagnosis/procedure slots cannot establish NIS annual semantics.

Only the pkgdown site workflow was found. No R CMD check workflow, tags, or releases were present at review time. easyNIS needs package checks, numerical validation, and release evidence from its first implementation stages.

The survey wrapper documents a single-year limit but checks design columns rather than enforcing that limit. Its warning describes collecting a full table, whereas tests expect lazy variables. Actual memory behavior needs a focused prototype before a similar interface is adopted. Documentation should state the validated behavior of each estimator.

The [license](https://github.com/AliSalman-et-al/easyNRD/blob/82a55a96a82e1302828b60bad766226b883af101/LICENSE) says 'Copyright 2026 Ali Salman. All rights reserved.' Public visibility does not establish permission to redistribute copied code under easyNIS's MIT license. Saad chose independent implementation first.

## Transfer assessment

Learn from the managed session pattern, safe SQL quoting, lazy transforms, narrow projections, synthetic fixtures, cleanup checks, vignettes, and comparisons with survey reference calculations. Rebuild the annual NIS metadata, import/join, missingness, coding, weight/design, pooling, and analysis contracts.

Do not transfer `NRD_VISITLINK`, `NRD_DAYSTOEVENT`, index/readmission windows, first-per-patient logic, NRD design names, or readmission-oriented sort assumptions. NIS is a discharge analysis workflow with no longitudinal patient linkage.

The local clones are `Documents/easyNRD` for Ali's upstream and `Documents/easyNRD-public` for Saad's fork. Their tracked contents were left unchanged. Local book copies sit in ignored reference folders.
