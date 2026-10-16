# Analyst workflow and redesign direction

This note records how our NIS analysts work today and the direction of the
slim easyNIS redesign. It summarizes a code-only survey of about 55 internal
NIS study projects (2026-10-16). It contains no record data, results, private
paths or project-specific findings.

## How analysts work today

1. A prep script per study opens yearly parquet files (Core, Hospital,
   Severity and cost-to-charge ratios merged, plus Stata-derived Elixhauser and
   Charlson columns), relabels about 25 coded columns with `case_when()`,
   flags conditions with regular expressions on a comma-joined diagnosis
   string, inflates charges with hard-coded CPI values and writes a study
   parquet.
2. A Quarto website per study reads that parquet, sets factor references,
   builds a `survey::svydesign()`, subsets the cohort, and reports a
   `gtsummary` baseline table, outcome tables and one `svyglm()` per outcome.
3. Each study keeps a `labels.R` with variable labels, and a `TESTING`
   switch for a small sample.

Most studies use 2018–2020; recent studies use 2017–2022.

## Recurring problems the package must remove

- Survey design columns that do not exist after 2012 (`HOSPID`, `TRENDWT`),
  and strata/hospital identifiers that are not year-specific when years are
  pooled.
- Cohort rows filtered before the design is built, which gives wrong
  standard errors.
- Column names that change case between years (2022 renames the APR-DRG
  severity and DRG/MDC "NoPOA" columns), silently producing missing values
  in pooled data.
- Regular expressions that match across neighbouring codes, only test the
  first diagnosis, or match unintended code families.
- Elixhauser indicator columns mapped to the wrong comorbidity by number.
- Charges reported as costs; CPI values hard-coded in every script.
- The same labels and reference levels retyped in every study, with drift.
- Covariate lists pasted once per outcome model.
- No suppression of cells based on 10 or fewer discharges.
- Deaths counted as non-home discharges.

## Direction

- Scope: NIS 2012 onward; first target 2017–2022 (ICD-10-CM/PCS only).
  ICD-9 years (2012–Q3 2015) are a later increment.
- Thin and pipe-first: data-first functions that return tibbles or srvyr
  designs. Build on arrow, dplyr, srvyr, survey and gtsummary; do not wrap
  what one dplyr or srvyr line already does.
- One step: a single Quarto file per study goes from parquet to report.
- `nis_design()` hard-codes the 2012+ specification (year-specific
  `HOSP_NIS` clusters and `NIS_STRATUM` strata, `DISCWT` weights) and
  collects only cohort rows plus one placeholder row per hospital-year.
  An equivalence test against the full design gates this method.
- Prefix code lists replace regular expressions; each diagnosis column is
  tested separately.
- `nis_label()` applies HCUP value labels, reference levels and variable
  labels, so studies no longer need `labels.R`.
- `nis_cost()` computes cost from `CCR_NIS` with a bundled CPI-U table.
- `nis_suppress()` masks gtsummary cells based on 10 or fewer discharges.
- `nis_new_study()` creates a study folder from the Quarto template; an
  invented `nis_example()` dataset replaces `TESTING` switches.

Scientific choices (placeholder-row variance, pooled weights, cost method)
remain experimental until Saad and Ali approve them.

## Follow-on handoff

The study template should use
`purrr::map()` over outcomes, include `factor(YEAR)` among covariates, and show
plain lazy flow-count chunks. Its self-contained HTML and DOCX output should
hide code, use the JAMA theme, and include Methods, flow, Table 1, outcomes,
trends, and models. The optional IPTW example remains commented out because
propensity weighting is experimental. The template must not imply HCUP
endorsement or scientific approval.

Keep placeholder-row design methods experimental. Do not attribute the method
to HCUP based on an inaccessible appendix. Gate it against a full-data survey
design for coefficient estimates, standard errors, and degrees of freedom.
The Quarto template, `nis_new_study()`, and final README decisions belong to the
separate template increment.
