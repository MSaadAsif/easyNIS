# easyNIS

**A tidy, reproducible workflow for opening, defining cohorts in, and analysing HCUP National Inpatient Sample (NIS) data with survey weights.**

[![R-CMD-check](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/R-CMD-check.yaml)
[![Lint](https://github.com/MSaadAsif/easyNIS/actions/workflows/lint.yaml/badge.svg)](https://github.com/MSaadAsif/easyNIS/actions/workflows/lint.yaml)
[![Codecov test coverage](https://codecov.io/gh/MSaadAsif/easyNIS/branch/main/graph/badge.svg)](https://codecov.io/gh/MSaadAsif/easyNIS)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/MSaadAsif/easyNIS/blob/main/LICENSE)

## Why easyNIS?

NIS analysis often repeats the same file opening, code-prefix matching, survey-design setup, and disclosure review in every study. easyNIS provides pipe-friendly helpers for those steps while leaving study definitions and statistical decisions with the analyst. Annual Parquet files open lazily through Arrow; `nis_design()` prepares a `srvyr` design; and `nis_example()` supplies invented offline data for learning and examples.

## Install

```r
pak::pak("MSaadAsif/easyNIS")
```

## Quick start

This complete example uses only the package's invented offline fixture. It does not need HCUP files.

```r
library(easyNIS)

path <- nis_example(years = 2019:2020)
nis <- nis_open(path) |>
  nis_flag_dx(heart_failure = "I50")

design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 18,
  keep = c(AGE, FEMALE, DIED, LOS)
)

srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_age = srvyr::survey_mean(AGE)
)
```

The example records and code values are invented. To analyse real data, use files you are authorized to access and follow the HCUP Data Use Agreement.

## Functions by task

| Task | Functions |
| --- | --- |
| Open and flag | `nis_example()` creates invented Parquet fixtures; `nis_open()` opens annual Parquet data lazily; `nis_flag_dx()` and `nis_flag_pr()` add diagnosis and procedure prefix flags. |
| Design and weighting | `nis_design()` prepares a survey design for a declared cohort; `nis_reweight()` multiplies its cohort weights (experimental). |
| Comorbidity and CCSR | `nis_comorbidity()` adds AHRQ Elixhauser Refined indicators through `medicalcoder` (experimental); `nis_ccsr_codes()` reads code mappings from an HCUP CCSR reference file you supply (file layouts unverified). |
| Labels and costs | `nis_label()` applies supported HCUP labels; `nis_cost()` adjusts charges and cost estimates using the package's CPI-U series and `CCR_NIS` (experimental method). |
| Suppression and study setup | `nis_suppress()` masks small unweighted cells in a `gtsummary` result; `nis_new_study()` creates a Quarto study folder from the package template. |

See the [function reference](https://msaadasif.github.io/easyNIS/reference/index.html) for arguments and details.

## Supported years and limitations

The package accepts NIS data years 2012 onward. This describes the supported input range, not verification of every annual layout or scientific approval of the methods.

- **ICD-10:** The default diagnosis and procedure flaggers target the `I10_DX*` and `I10_PR*` slots.
- **ICD-9, 2012–2015:** Experimental. The code treats 2012–2014 and 2015 Q1–Q3 as ICD-9, with Q4 2015 ICD-10. The 2015 coding transition is documented, but some annual slot-layout and version-metadata assumptions are **UNVERIFIED** against primary HCUP layouts. `docs/ICD9-SUPPORT.md` records the evidence and assumptions. No crosswalk or clinical code list is bundled.
- **NIS 2023:** Experimental and **UNVERIFIED** against official 2023 documentation or real 2023 data. Assumptions include the `TOTCHG_2023` field, removed geography fields, and sequential stratum identifiers. The distinct 2023 charge field is not silently combined with `TOTCHG`.
- **CCSR CSV/Excel layouts:** The reader validates expected fields and code shape, but its assumptions about downloaded HCUP reference-file layouts are **UNVERIFIED**. No CCSR content is bundled.
- **Variance and cost methods:** The zero-domain placeholder-row variance method and cost adjustment remain experimental pending scientific approval. CPI-U adjustment uses the included annual series; cost estimates additionally require the appropriate `CCR_NIS`. Review methods and outputs for your study.

Read the [Getting started vignette](https://msaadasif.github.io/easyNIS/articles/getting-started.html) and the [porting guide](https://msaadasif.github.io/easyNIS/articles/porting.html) for worked workflows. The [analyst workflow note](https://github.com/MSaadAsif/easyNIS/blob/main/docs/ANALYST-WORKFLOW.md) explains the redesign context.

## Data use and privacy

NIS data are licensed by HCUP and subject to its Data Use Agreement. Never share or commit record-level data, including accidentally copied or derived record-level files. Review all output before sharing; easyNIS suppresses unweighted cells at or below 10 by default in its suppression helper, but suppression does not automatically prevent every form of inference. Follow your institution's disclosure rules and the applicable HCUP requirements.

## Citation

If easyNIS supports your work, cite the package and the version used. In R, run:

```r
citation("easyNIS")
```

Please also cite the HCUP NIS and any methods or code-set references used in your analysis.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, checks, style, and privacy requirements. Please use GitHub Issues for bugs and feature requests; use GitHub Discussions for questions when enabled.

## License

easyNIS is available under the MIT License. See the [LICENSE file](https://github.com/MSaadAsif/easyNIS/blob/main/LICENSE).
