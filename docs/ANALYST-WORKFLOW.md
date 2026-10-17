# Analyst workflow

easyNIS provides pipe-friendly tools for preparing Nationwide Inpatient Sample
(NIS) data for analysis. Start with `vignette("getting-started", package =
"easyNIS")` for an end-to-end workflow or `vignette("porting", package =
"easyNIS")` when adapting an existing study.

## Prepare data

Open annual Parquet files with `nis_open()`. The package preserves the source
records and offers helpers for diagnosis and procedure flags, labels,
comorbidity scores, and inflation-adjusted costs. `nis_ccsr_codes()` reads an
HCUP CCSR reference file so analysts can build study-specific code lists.
Use `nis_example()` to explore the API with invented data.

## Design and estimate

Use `nis_design()` to create a NIS survey design with year-specific hospital
and stratum identifiers, discharge weights, and optional domain restrictions.
Use survey-aware analysis functions for estimates and standard errors.
`nis_reweight()` adds experimental propensity-based weights for analyst-led
evaluation; it does not replace the supplied NIS discharge weight or the
survey design.

## Protect outputs

Follow the applicable HCUP Data Use Agreement when producing tables and
sharing results. `nis_suppress()` masks small cells and related totals in a
table, but analysts must review all derived outputs for disclosure risk.
Use only invented public fixtures in package examples and tests. Never commit
licensed inputs, private paths, local validation receipts, or record-derived
output.

## Experimental support

ICD-9 support through the third quarter of 2015 and NIS 2023 layout handling
are experimental. The 2023 layout and historical ICD-9 field details are not
verified against official source files. Review the package documentation and
`docs/ICD9-SUPPORT.md` before relying on these features.
