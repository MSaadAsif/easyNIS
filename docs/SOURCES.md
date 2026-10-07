# Evidence and research sources

Reviewed 2026-10-08. These sources inform the plan; annual metadata and licensed validation are still separate implementation tasks. Methodological proposals in PLAN.md are recommendations unless listed as confirmed decisions. Source availability and policies should be checked again at release/submission time.

## HCUP sources

| Source | Finding used | Consequence for easyNIS |
|---|---|---|
| [NIS overview](https://hcup-us.ahrq.gov/nisoverview.jsp) | Releases currently span 1988–2023; annual component availability differs. | Maintain an explicit coverage/capability matrix. |
| [2023 introduction](https://hcup-us.ahrq.gov/db/nation/nis/NISIntroduction2023.pdf) | Removed race/hospital geography, consolidated rurality, adjusted total charges, recoded identifiers/strata. | Separate adapter and comparability limits. |
| [2021 introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2021.jsp) | Documents modern design and the 2012 sampling change. | Era-aware design/weight rules. |
| [2015 introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2015.jsp) | ICD-9-CM Q1–Q3 and ICD-10-CM/PCS Q4 are separate parts. | Preserve coding/quarter provenance. |
| [1998 redesign report](https://hcup-us.ahrq.gov/db/nation/nis/reports/Changes_in_NIS_Design_1998.pdf) | Sampling and hospital definitions changed. | Historical support requires a reviewed design boundary. |
| [Trend-weight documentation](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp) | TRENDWT spans 1993–2011; year/hospital joins; zero weights can be valid; 2000 has a charge-specific weight. | Weight selection depends on era and estimand. Do not extrapolate to 1988–1992. |
| [HCUP coding practices](https://hcup-us.ahrq.gov/db/coding.jsp) | Numeric special-missing values depend on field width; character conventions differ. | Parse documented formats rather than replacing every negative value with NA. |
| [Nationwide SAS load programs](https://hcup-us.ahrq.gov/db/nation/sasloadprog.jsp) | Official component/year layouts; pre-1998 programs are in the cumulative archive. | Audit registry facts against original layouts and retain provenance. |
| [File specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp) | Annual layouts/counts support import verification. | Check component shapes and revisions. |
| [Summary statistics](https://hcup-us.ahrq.gov/db/nation/nis/nissummstats.jsp) | Official annual summaries provide reference checks. | Compare aligned definitions; account for rounding and known differences. |
| [Database documentation](https://hcup-us.ahrq.gov/db/nation/nis/nisdbdocumentation.jsp) | Includes annual information and known issues/corrections. | A year is not a complete release-revision identifier. |
| [Standard-error tutorial](https://hcup-us.ahrq.gov/tech_assist/standarderrors/508/508course_2016.jsp) | Design-based variance estimation uses clustering and stratification. | Ordinary weighted averages/models are not a survey-inference substitute. |
| [Multi-year reference example](https://hcup-us.ahrq.gov/tech_assist/trends/interactive/pdfs/reference.pdf) | Official SAS example uses year in strata/domain specification. | Validate the R pooling/domain translation independently. |
| [Variance methods report](https://hcup-us.ahrq.gov/reports/methods/2015-09.pdf) | Pre-filtering can remove hospitals and affect domain standard errors. | Construct the full design before domain selection. |
| [Nationwide DUA](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp) | March 2026 guidance prohibits redistributing HCUP records and warns against publishing values 1–10 inclusive; proprietary tools have separate restrictions. | Invent public fixtures and review public exports. |
| [NIS analysis checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp) | Discharge-level scope, annual hospital identifiers, analysis/publication precautions, citations and hospital contribution checks. | Avoid longitudinal/readmission/state claims and add disclosure review. |
| [HCUP cost-to-charge files](https://hcup-us.ahrq.gov/db/ccr/costtocharge.jsp) | Annual supplemental ratios estimate inpatient resource costs and have their own availability/coverage. | Do not relabel charges as costs; validate joins and derivations. |
| [Refined Elixhauser documentation](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/comorbidity_icd10.jsp) | Current measures differ from older coding algorithms and some require POA. | Version algorithms and refuse unsupported complete index calculation. |

The older checklist's small-cell wording and current DUA wording differ. The planned default uses the current DUA's inclusive 1–10 guidance, with complementary suppression and hospital-contribution review. Publication checks remain subject to applicable agreements and manuscript context.

For reference, common ASCII numeric patterns represent missing with negative 9-filled values, invalid with negative 8-filled values, historical source-unavailable with negative 7-filled values, inconsistent with negative 6-filled values, and historical not-applicable with negative 5-filled values. Their SAS counterparts include `.`, `.A`, `.B`, `.C`, and `.N`. Actual rules must be obtained per field; conversion to parquet may already have lost the reasons.

## R package and statistical sources

| Source | Use in the plan |
|---|---|
| Supplied *R packages*, Hadley Wickham, June 29, 2015 | Structure, metadata, help, vignettes, tests, namespace, examples, checks and releases. [Chapter/page map](references/README.md). |
| [R Packages, second edition](https://r-pkgs.org/) | Current development workflow and teaching reference. |
| [Package structure](https://r-pkgs.org/structure.html) | Source/built forms and build exclusions. |
| [Testing basics](https://r-pkgs.org/testing-basics.html) | Behavioral/numerical tests with testthat. |
| [Release guidance](https://r-pkgs.org/release.html) | Checks, documentation, release preparation. |
| [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html) | Authoritative package structure, metadata, namespace and check requirements. |
| [CRAN policies](https://cran.r-project.org/web/packages/policies.html) | Dependency, example, resource, portability and submission expectations. |
| [Survey design](https://r-survey.r-forge.r-project.org/survey/html/svydesign.html) | Nonmissing design variables, nested design construction and inference choices. |
| [Survey domain subsetting](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/subset.survey.design.html) | Preserves original design information during subpopulation analysis. |
| [Survey GLMs](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svyglm.html) | Design-based fits, quasi families, effect interpretation and denominator-df behavior. |
| [gtsummary survey tables](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html) | Weighted statistics and explicit unweighted counts; display labels need careful interpretation. |
| [gtsummary regression tables](https://www.danieldsjoberg.com/gtsummary/reference/tbl_regression.html) | Formatting existing model results without replacing inference. |
| [gtsummary to flextable](https://www.danieldsjoberg.com/gtsummary/reference/as_flex_table.html) and [Word export](https://davidgohel.github.io/flextable/reference/save_as_docx.html) | Proposed adapter route for the agreed Word table exports. |
| [HCUPtools](https://cran.r-project.org/web/packages/HCUPtools/index.html) | Existing public classification/summary resources; does not load purchased NIS records. |
| [touch](https://cran.r-project.org/web/packages/touch/index.html) | Existing comorbidity and mapping tools for comparison/adapters. |

## Publication sources

[JOSS submission guidance](https://joss.readthedocs.io/en/latest/submitting.html) currently requires substantial, feature-complete research software, sustained public development for more than six months, demonstrated research use, and open-source practices. It also requires disclosure of AI assistance and human responsibility for the scientific/design decisions. Confirm current requirements before submission.

[The R Journal submission guidance](https://journal.r-project.org/submissions.html) requires package availability on CRAN/Bioconductor and stresses maturity, numerical unit tests, complete help, workflow vignettes, and comparison with existing approaches. It remains an alternative venue.

## Repository evidence

The [easyNRD audit](EASYNRD-REVIEW.md) links inspected files at a fixed commit rather than relying on a moving branch. Its useful design patterns, current license, limited era coverage, CI gaps, and documentation discrepancies informed the independent easyNIS plan.

## Limits of this research

No patient-level NIS files were loaded or analyzed in this planning session. Local codebooks, scripts, and report methodology supplied additional context through the [Biostatistics review](CONTEXT-REVIEW.md). No package numerical tests were run because easyNIS implementation does not yet exist. Historical finite-population/design choices, exact annual metadata, model inference defaults, and difficult disclosure cases require the stated review and validation gates.
