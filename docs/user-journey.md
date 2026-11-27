# The easyNIS analyst journey

Start with the full discharge sample for the study years. Define the cohort
with flags, preserve the sampling fields through the lazy query, and estimate
within a survey domain. Keep numerical outputs private until disclosure review.

## From annual files to a shareable result

| Step | Recurring work in study scripts | easyNIS path | Remaining friction |
| --- | --- | --- | --- |
| Open | Convert files by hand, bind annual data, and source shared setup code. Some source paths fail outside the original project. | `nis_open(path, years = ...)` scans annual Parquet and checks releases. | Conversion, release revisions, and private path setup need a documented handoff. |
| Define the cohort | Construct numbered slot vectors, match prefixes, and apply inclusion and exclusion filters. An any-position definition can accidentally check only the first slot. | `nis_flag_dx()` and `nis_flag_pr()` default to any slot. Specify principal or secondary explicitly where needed. Use `nis_attrition()`, `nis_dx_sensitivity()`, and `nis_audit_code_transition()` to audit choices. | A definition spanning October 2015 needs two calls and a manually combined flag. Analysts also repeat the same eligibility predicates for attrition and for the design. |
| Clean and label | Repeat long `case_when()` recodes. Reused recodes can swap discharge categories or collapse distinct kinds of missingness. | Use original codes for predicates. `nis_design()` labels retained variables after collection, and `nis_label()` works on collected tables. | Some official fields still carry raw codes. Keep annual definitions distinct, especially where categories changed. |
| Select columns | Maintain hand-built slot lists and collect wide inputs before trimming them. | `select(nis_vars_design(), nis_vars_dx(), ...)` projects columns lazily. Use `keep` in `nis_design()` for the final model and table variables. | Joined fields and custom outcomes still need explicit names. A missing required design field raises an error at design construction. |
| Build the design and choose domains | Recreate weights and survey formulas across analyses and sometimes filter the raw sample first. | Declare an eligibility expression in `nis_design(cohort = ...)`. Use survey-aware subsetting for secondary analyses. | Document which filters define study years and which define domains, and verify secondary filtering against a full-sample design. |
| Prepare outcomes and covariates | Recode mortality, LOS, disposition, hospital categories, and comorbidity in several scripts. | Use `DIED`, `LOS`, `nis_cost()`, and an explicitly versioned `nis_comorbidity()` workflow. | Cost inputs and hospital attributes need correct year-specific linkage. POA availability can change how comorbidities are assigned. |
| Describe and model | Build baseline tables and fit regressions in separate scripts that may use different denominators. | Reuse the design with `srvyr`, `gtsummary::tbl_svysummary()`, and `survey::svyglm()`. Report the model denominator and missingness. | Provide a reproducible survey table and model example with audited cell counts. |
| Suppress and export | Format and export tables and figures separately, then reconstruct the methods. | Pair estimates with `nis_cell_counts()` and run `nis_suppress()`. The private Quarto workflow can retain the analysis and decision record. | Record what ran and what was suppressed. Review disclosures across related outputs and export only the reviewed results. |

These observations are based on code review of analyst scripts and the
package's [12-study literature review](research/2026-10-nis-literature-report.md).
The shipped workflow uses invented examples. Clinical definitions, time
windows, confounders, and missing-data decisions belong to the study protocol.

## Evidence behind the defaults

- The NIS observation is a discharge. Khera et al. documented failures to
  account for the survey design and transitions, inappropriate hospital-level
  inference, and use of nonspecific secondary codes as in-hospital outcomes.
  Make the discharge-level survey design the default example, keep principal
  and any-position definitions explicit, and ask for defensible timing or
  POA evidence when identifying events during admission. [Khera et al., JAMA
  2017](https://doi.org/10.1001/jama.2017.17653)
- The HCUP variance report recommends the full sample for domain analysis.
  Its Appendix A preserves hospitals that contribute no domain discharges when
  using a subset. The addendum also covers entire hospitals with missing
  analytic values. Verify a rare domain's standard errors and degrees of
  freedom against full-sample `survey` calculations. [HCUP Methods Series
  2015-09](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp)
  · [Addendum](https://hcup-us.ahrq.gov/reports/methods/MS2015-09%20Addendum.pdf)
- The 2012 redesign changes trend weights for earlier years. The separate
  October 2015 ICD transition changes code availability and can interrupt
  trends. For 2012 onward, keep `DISCWT`, `YEAR`, and the relevant
  quarter and ICD version fields. Distinguish annual estimates, pooled totals,
  and average annual totals. Rubin et al. illustrate annual estimates with
  standard errors and an external denominator before fitting Joinpoint.
  [HCUP trend weights](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp)
  · [2015 Introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2015.jsp)
  · [Rubin et al., JAGS 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8373714/)
- Release metadata matters for both linkage and comparability. Use the annual
  file layouts and join Hospital or CCR fields within year. A corrected
  2019 or 2020 file can differ from the original release. [HCUP File
  Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp)
  · [2024 Introduction](https://hcup-us.ahrq.gov/db/nation/nis/NISIntroduction2024.pdf)
  · [Known 2019–2020 issues](https://hcup-us.ahrq.gov/db/nation/nis/correct_2019and2020.jsp)
- Preserve the unweighted and hospital denominators used in disclosure
  review, including for percentages and related totals. [HCUP NIS
  checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp)

## Ranked implementation briefs

Priority reflects how often a step recurs, the consequence of an error, and
how much manual work the fix removes. Effort is an estimate for one agent,
including invented-data verification and docs. Paths beginning with “new”
are proposed ownership boundaries.

| Rank | Work and proof | Effort / payoff | Ownership and files |
| --- | --- | --- | --- |
| 1 | Column groups and one worked pipeline. Verify identical survey estimates after projection, fail on missing design keys, and measure early versus late projection in separate R processes. | 1–2 days / high, every study projects and protects variance inputs | This change, `R/column-groups.R`, `tests/testthat/test-column-groups.R`, `vignettes/getting-started.Rmd`, `tools/benchmark-column-projection.R`. |
| 2 | Survey domains. Teach the distinction between a sampled universe and an analytic domain. Compare successive domain filters, including a hospital with no domain records, with conventional full-sample `survey` results. | 2–4 days / high, protects uncertainty | Design agent, `R/design.R`, `R/design-sample.R`, `R/cohort-design.R`, `vignettes/articles/survey-design.Rmd`. |
| 3 | Expand HCUP labels for residence and selected coded indicators. Verify official codes, preserve missing and unknown values, and keep format changes separate from recoding across eras. | 1 day / high, replaces repeated recodes | Label brief, `R/labels.R`, `tests/testthat/test-label-boundaries.R`, `man/nis_label.Rd`. |
| 4 | Define one flag with both analyst-supplied code sets, applying each only to its own slots. Compare against two explicit calls on mixed 2015 records and test single-era files, principal position, and ineligible quarters. Keep any-slot behavior as the default. | 2–3 days / high for cross-era projects | Flag brief, `R/code-flags.R`, `tests/testthat/test-flag-year-validity.R`, `vignettes/articles/code-transitions.Rmd`. |
| 5 | Show annual estimates and uncertainty before any trend model. Verify a pooled total, average annual total, and year-specific estimates on a fixture with missing quarters. Include year-as-covariate and Joinpoint input examples using existing modeling packages. | 3–5 days / high for multiyear studies | Trends agent, new `R/trends.R`, dedicated trend tests and article. |
| 6 | Convert annual files reproducibly and validate them before use. Check schema, year, protected fields, and failure cleanup without materializing a year in R. Include a corrected-release example. | 3–5 days / high at entry | Converter agent, converter modules and conversion documentation. |
| 7 | Guard collect operations and document memory budgets. Exercise bounded projected scans and an over-budget wide collect, retaining OS-level measurements. | 2–4 days / high for wide or pooled inputs | Collect agent, `R/duckdb.R`. Performance agent, budget evidence and docs. |
| 8 | Validate many-to-one hospital and CCR linkage on `YEAR` and `HOSP_NIS`. Prove there is no row multiplication, no mismatched-year join, and that unmatched rows remain visible. Scope to discharge-level analysis of hospital characteristics. | 2–3 days / high for hospital covariates and cost | Linkage agent, new linkage module, dedicated tests and article. |
| 9 | Keep standard outcomes readable and comparable. Verify DIED and disposition mappings, missing LOS handling, and year-specific charge inputs before conversion to cost. Keep clinical event definitions analyst supplied. | 2–3 days / medium-high | Outcomes agent, new `R/outcomes.R`, outcome tests and docs. |
| 10 | Share eligibility rules between attrition and the final domain. Start with named logical expressions or flags in one worked example. Verify that the last unweighted attrition count agrees with the domain denominator under the same missingness and design-validity policy. | 1–2 days / medium | Attrition brief, `R/attrition.R`, `tests/testthat/test-attrition-parity.R`, `vignettes/articles/cohorts.Rmd`. Coordinate any changes to domain inputs with the design agent. |
| 11 | Make comorbidity practical on lazy cohorts. Project the needed diagnosis and POA fields, score only eligible discharges, preserve unknowns, and compare with the existing collected path. | 2–4 days / medium-high | Comorbidity agent, `R/comorbidity.R`, comorbidity tests and article. |
| 12 | Demonstrate a weighted Table 1 and regression on the same design. Verify factors, missingness, p-values, and denominators with an invented benchmark. | 1–2 days / medium-high | gtsummary agent, `vignettes/articles/descriptives-models.Rmd` and dedicated workflow tests. |
| 13 | Produce a private methods paragraph and checklist receipt from what ran. Reconcile displayed estimates with suppression masks and verify suppressed values stay out of rendered tables, plots, and downloadable files. | 3–5 days / high for reporting | Reporting agent, `R/study-*.R`, `inst/templates/nis-study/`, study tests. |
| 14 | Qualify published-study reproduction and package readiness. Keep licensed-data verification private and verify public receipts contain only approved status and tolerance information. | 3–5 days / high for confidence | Published-study and readiness agents, their separate `tools/probe/` modules. |

Pre-2012 implementation, patient linkage, state estimates, and hospital volume
inferred from sampled discharges remain outside the package's standing scope.
Trend guidance can point to established modeling tools without choosing a trend
model or supplying a clinical crosswalk.
