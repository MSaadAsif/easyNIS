# easyNIS development plan

Prepared 2026-10-08 for Saad and Ali. Read [decisions](DECISIONS.md) for confirmed choices and open questions. The repository currently contains planning documents; the interfaces below are proposed and have not been implemented or tested.

## Intended result

A researcher with licensed NIS files should be able to identify the files' year and coding system, validate their structure, define a discharge cohort, construct an appropriate survey design, calculate descriptive estimates, fit regression models, and export reviewed publication tables. The workflow should be short enough to learn from one worked example. Its result should retain enough provenance for another researcher to repeat the analysis.

The first release covers 2017–2022 parquet files. Saad has 40 GB RAM. V1 includes survey-weighted linear, logistic, and Poisson-family models and descriptive/regression tables with CSV, HTML, and Word export. The eventual coverage target is 1988–2023, the years currently listed by HCUP, with future annual releases added after review. Saad maintains easyNIS; Saad and Ali review methodological changes. JOSS is the primary paper target.

The package must distinguish an imported file from a validated analysis. It must also distinguish a technically supported year from a year that is comparable for a particular research question. A file can be readable while a requested variable, phenotype, or trend analysis is unavailable or inappropriate.

## What we can learn from easyNRD

The existing easyNRD has useful DuckDB/parquet ingestion, SQL phenotyping, resource management, per-year processing, survey integration, synthetic tests, and vignettes. It gives us a practical starting vocabulary and examples of large-data workflows. [The audit](EASYNRD-REVIEW.md) records the inspected commit and limitations.

easyNIS needs its own contracts for components, variables, missing values, diagnosis slots, identifiers, weights, and annual changes. NIS discharges cannot be linked into longitudinal patients or readmissions. We should not carry over NRD timing, visit-link, first-per-patient, or readmission-window functions.

The [Biostatistics context review](CONTEXT-REVIEW.md) also examined the team's earlier preparation/analysis projects, local codebooks, and rendered reports. It adds explicit input profiles for custom conversions, raw-code preservation, code-set/algorithm provenance, outcome-scale checks, and validation cases drawn from repeated legacy assumptions. The detailed private inventory and source evidence remain in the ignored local reference folder.

The current easyNRD license reserves all rights. MIT applies to newly written easyNIS code. Direct copying needs Ali's permission and compatible licensing first. We should keep easyNIS independently installable and consider a shared core only after both packages demonstrate stable repeated needs.

## Research boundaries that shape the design

| Boundary | Why it matters | Required behavior |
|---|---|---|
| 1988–1992 | Earlier files and weights need separate review; the official trend-weight product starts in 1993. | Import support must not imply comparability with modern trends. |
| 1993–1997 | Historical names, file layouts, missing codes, and sample definitions differ. | Use audited annual metadata and applicable trend weights. |
| 1998 | Hospital sampling and definitions changed. | Record the redesign and corrected release versions. |
| 2000 charge analyses | HCUP supplies a special historical charge trend weight. | Select weights by year and estimand, not only year. |
| 2002/2005 | Supplemental component availability changes. | Report which components exist and which were supplied. |
| 2012 | NIS moved to sampling discharges and changed its hospital universe. | Build era-specific design and trend rules. |
| 2015 | ICD-9-CM Q1–Q3 and ICD-10-CM/PCS Q4 are separate parts. | Preserve quarter/coding provenance; require era-specific cohort definitions. |
| 2016–2017 | Diagnosis/Procedure Groups is unavailable. | Do not treat the absent component as a broken import. |
| 2018 onward | Derived classification fields and tool versions change. | Track component and classification-version provenance. |
| 2023 | Race/geography availability, rurality, adjusted charges, strata, and identifiers change. | Do not invent missing variables or silently equate adjusted charges with historical charges. |

These are planning boundaries, not an audited annual registry. The source documents and caveats are linked in [SOURCES.md](SOURCES.md). Each adapter still requires its own annual load-program and data-element review.

## Proposed user workflow

This sketch illustrates the intended learning path. Names, argument shapes, and classes require API review before implementation. It is not executable code yet.

```r
library(easyNIS)

nis_supported_years()

session <- nis_open("analysis.duckdb")
tryCatch({
  stays <- nis_import(
    session,
    core = "NIS_2022_Core.parquet",
    hospital = "NIS_2022_Hospital.parquet",
    year = 2022
  )
  report <- nis_validate(stays)
  stays <- nis_harmonize(stays)
  stays <- nis_flag_codes(
    stays, name = "study_cohort", codes = reviewed_codes,
    system = "ICD10CM", scope = "any_diagnosis"
  )

  # Select columns, retain the complete eligible NIS design population.
  design <- nis_design(
    stays,
    variables = c("study_cohort", "died", "age", "sex", "payer", "los"),
    estimand = "annual"
  )
  cohort <- nis_domain(design, study_cohort)

  fit <- nis_model(
    cohort, died ~ age + sex + payer,
    family = quasibinomial(), missing = "complete_case"
  )
  table1 <- nis_table(cohort, variables = c("age", "sex", "payer", "los"))
  table2 <- nis_model_table(fit, effect = "odds_ratio")
  nis_export_table(table1, "table1.docx")
  nis_export_table(table2, "table2.csv")
  nis_analysis_report(cohort, models = list(fit), path = "analysis-report.html")
}, finally = nis_close(session))
```

The licensed-data workflow should be mirrored by a fully executable synthetic example. The quickstart should explain discharge versus patient, weights versus raw counts, domain analysis, odds ratios, and unavailable-year errors at the point they matter. Detailed statistical choices belong in methods vignettes and the analysis report.

## Proposed module responsibilities

| Module | Responsibility | Principal output |
|---|---|---|
| Year metadata | Describe components, aliases, types, missing formats, design rules, slot counts, and revisions. | Auditable registry and capability lookup. |
| Import and storage | Read supported local files, validate conversions, own connections, and close resources. | Discharge relation with release metadata. |
| Validation and joins | Check required fields, keys, cardinality, values, counts, and component coverage. | Structured errors/warnings and a validation report. |
| Harmonization | Provide documented common meanings while preserving original source semantics. | Canonical analysis variables and transformation provenance. |
| Cohorts | Match reviewed code sets in specified slots and coding eras. | Flags with code-set version and eligibility definition. |
| Survey and pooling | Construct the complete design, define domains, and select estimand-specific weights. | Standard survey design plus provenance. |
| Models | Fit supported survey GLMs and record diagnostic/missingness information. | Original survey fit and structured results. |
| Tables and disclosure | Produce descriptive/regression tables and inspect disclosure risks before export. | Numeric results, presentation output, and review report. |
| Reproducibility | Record package/dependency versions and analysis decisions. | Portable analysis specification and sanitized report. |

Avoid a universal HCUP abstraction at this stage. Keep NIS rules in the NIS registry, public functions small in number, and transformations inspectable. Return standard R objects where practical so users can continue with established tools.

## Annual metadata contract

For each year and revision, store component names, expected columns and types, identifier fields, hospital joins, diagnosis/procedure field lists, coding systems, missing-value rules, survey fields, available classifications, software versions, and source references with retrieval dates/checksums. Each fact should point to its official definition rather than a neighboring year's assumption.

Record separately whether a variable is unavailable in the source, missing in an individual discharge, omitted by the user's parquet conversion, or removed by a user projection. This distinction prevents accidental interpretation of an absent column as an observed zero or an ordinary missing value.

Parquet files may already have lost SAS labels or special-missing reasons. Import must detect what can be established and report what cannot be recovered. Do not label unknown conversion provenance as equivalent to raw HCUP data. Preserve codes and identifiers without numeric coercion or loss of precision. Use documented aliases; reject collisions after normalizing names.

Source fields should remain recoverable. Common categorical variables need explicit level definitions and year applicability. New variables must document derivations and units. Treat charges, CCR-derived costs, adjusted 2023 charges, and inflation-adjusted values as distinct quantities.

## Import and component joins

Parquet is the agreed v1 release-tested input target. Additional importers follow after the full workflow is verified. For raw ASCII later, use audited official fixed-width layouts and missing-value formats; never execute downloaded load-program code inside the R session. SAS/Stata/SPSS support should preserve labels and tagged missing values where the chosen reader permits it.

Begin by inventorying the actual 2017–2022 conversions: file paths, component coverage, release revisions, row/column counts, types, labels, and conversion provenance. Keep this inventory local and publish only a sanitized support summary.

Distinguish parquet that preserves official source columns from merged/recoded analytical exports. Local codebooks demonstrate that a modern annual discharge weight can have a locally renamed field, and that a modern hospital identifier can have a historical-looking name. A name alone must not select the weighting methodology. Require a verified conversion profile or explicit reviewed mapping, check consistency with the data year, and preserve the original supplied fields. Report irrecoverable labels/missing reasons and whether the input has already been cohort-filtered. A reduced study dataset cannot silently be treated as the complete source design.

Use annual discharge identifiers for discharge components and annual hospital identifiers for Hospital joins. Include year and, where necessary, coding part in pooled keys. Validate component key uniqueness before joining. Report unmatched keys and conflicting duplicate variables; fail on unintended row multiplication. A missing optional component should produce an explicit capability limit.

Historical `KEY`/`HOSPID` and modern `KEY_NIS`/`HOSP_NIS` need their own adapters. Modern hospital identifiers are reassigned annually and cannot establish a longitudinal hospital panel.

## Cohort definition

Start with explicit ICD-10-CM and ICD-10-PCS code sets for 2017–2022. Support exact codes and reviewed prefixes, distinguish principal/secondary/any-diagnosis scopes, and define how missing slots affect a flag. Avoid treating an arbitrary regular expression as a clinically validated phenotype.

Derive the actual slot list from annual metadata and observed columns. A study using all available diagnosis slots can change case ascertainment across years; record its slot policy and provide a common-slot sensitivity workflow. Preserve leading zeros, normalize case/decimals only under a documented coding-system rule, and verify SQL/R matching agreement.

Record code-set author/source, version, valid years/quarters, diagnosis versus procedure meaning, and review status. A user-defined condition is supported without promising clinical validity. Add adapters for established comorbidity/classification tools after checking tool versions and licenses. Do not claim exact ICD-9/ICD-10 equivalence from a simple mapping.

Validate code-set syntax, ranges, ambiguous letter/digit transcription, duplicate codes and classification mappings. Diagnosis CCSR mappings can involve multiple categories; joins must not multiply discharge rows. Codebook examples and copied clinical constants need clinical review before becoming package defaults. Supplied Charlson/Elixhauser flags are not automatically equivalent to current AHRQ refined measures or indices. Record the algorithm, principal/secondary scope, scoring variant, version and prerequisites. Do not fabricate POA information or compute a complete refined index from incomplete inputs. [AHRQ refined Elixhauser documentation](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/comorbidity_icd10.jsp)

For classification-frequency validation, match the tool version, principal-default versus all-category definition, and within-discharge deduplication used by the reference. Suppressed frequency cells are not zeros. If procedure timing is later exposed, derive earliest/latest time from valid matching procedure-day values; slot order is not a chronological guarantee.

## Survey design and pooled estimates

Use `survey` as the statistical reference implementation. HCUP documents clustering/stratification for variance estimation. Construct the complete design before selecting a disease cohort; retain all required design variables and only the analysis columns needed for the selected workflow. [HCUP variance guidance](https://hcup-us.ahrq.gov/reports/methods/2015-09.pdf) and [survey domain documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/subset.survey.design.html) inform this contract.

For pooling, create year-specific strata and hospital identifiers with nesting according to the reviewed annual design. Report whether the result is an annual estimate, a combined multi-year total, an average annual total, or a pooled proportion. Do not automatically divide weights by the number of years. Year composition and trend models require explicit review.

Use applicable historical trend weights for 1993–2011 when the estimand requires comparability, and current annual weights from 2012 onward. Valid zero trend weights must not be rejected as ordinary invalid weights; their treatment needs reference validation. The special 2000 charge weight and the lack of equivalent 1988–1992 trend weights need separate routing. [Official trend-weight documentation](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp)

Fail clearly on missing design fields, invalid/nonfinite weights, incompatible pooled data, or unknown design rules. Show PSU/stratum counts, degrees of freedom, and singleton strata. Do not silently change lonely-PSU settings, invent an FPC, or mutate global survey options. The approved inference choices must appear in the result provenance.

Required examples include a cohort absent from some hospitals, reused identifiers across years, varying year weights, and a missing outcome. Validate point estimates and standard errors, not only object classes.

## Models in v1

Fit user-specified formulas using `survey::svyglm()`. Proposed supported families are Gaussian linear regression, quasibinomial logistic regression, and quasipoisson log-link regression. Distinguish an odds ratio from a risk/rate ratio and from a mean difference; exponentiation should follow the family/link and requested interpretation. [Survey GLM documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svyglm.html)

The model interface should expose an analytic domain, outcome, covariates, family/link, confidence level, and missing-data policy. For complete cases, record excluded records and reasons while preserving the design's domain semantics. Leave imputation, survival, propensity methods, and longitudinal models to later extensions.

Preserve the native fit for standard R methods. A model report should include the formula, analysis years, code-set/domain definition, sample accounting, design degrees of freedom and inference policy, coefficient estimates, standard errors, intervals, p-values, reference categories, convergence warnings, rank deficiency, separation concerns, and sparse levels. Distinguish package checks from a researcher's judgment about confounding, model specification, and causal interpretation.

For count or continuous outcomes, document distribution/link assumptions and outcome restrictions. LOS and charges need examples that explain skewness and units. Do not offer one automatic 'best model' based only on a variable name. Test each supported family against explicit `survey` reference fits, including pooled-year covariates and factor interactions.

If a formula transforms an outcome, report the modeled scale and explain any back-transformation. Exponentiating a Gaussian coefficient from `log1p(outcome)` does not make it an odds ratio or automatically recover a difference in the arithmetic mean. Validate raw identifiers before constructing compound year-specific keys, and test legitimate zero-variance estimates rather than requiring every standard error to be strictly positive.

## Publication tables in v1

Create a structured numeric result before rendering. Table 1 should distinguish unweighted observed discharge counts, weighted national estimates, weighted percentages, and missingness. Table 2 should report effect measure, estimate, interval, p-value, adjustment variables, analysis population, years, and inference policy. Show units and reference groups. Test that rounding and rendering do not change numeric results.

`gtsummary` is a proposed presentation adapter, with `gt` for HTML and `flextable`/`officer` for Word as optional dependencies. Its survey tables and regression tables support established workflows, but formatting must not replace verified survey inference. Plain CSV/structured results should remain usable without the Word/HTML stack. [Survey summary table documentation](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html), [regression table documentation](https://www.danieldsjoberg.com/gtsummary/reference/tbl_regression.html)

The current nationwide DUA says to avoid publishing values 1–10 inclusive. Proposed export checks therefore use the underlying unweighted count, contributing hospitals, and margins, with primary and complementary suppression. Check percentages and derived values that reveal suppressed counts; do not leave raw counts in hidden export fields, footnotes, or a second format. Retain an internal numeric result locally but export only the reviewed presentation result. The checks aid review and do not certify a complete manuscript. [Current DUA](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp), [NIS checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp)

Require synthetic edge cases with raw counts 0, 1, 9, 10, and 11, a large weighted count generated by a small raw cell, one contributing hospital, complementary recovery through totals, and the same table exported in every supported format. Document how legitimate zero cells are displayed.

## Large-data strategy

Prototype DuckDB-backed parquet import and cohort preparation before committing to the backend contract. Push column selection and matching to the storage layer. After cohort flags exist, keep wide diagnosis/procedure columns out of model memory. Estimate the projected analysis object's memory before collection and give a useful message if it exceeds the configured budget.

The baseline correctness reference is a standard R `survey` design on invented data. Test any disk-backed survey option against that reference before adopting it. DuckDB and srvyr laziness do not automatically guarantee that every estimator/model remains out of memory.

Benchmark cold and warm runs for one full year and 2017–2022 pooling on Saad's 40 GB machine, using the actual column set. Record import/flag/design/model/export time, peak RAM, disk use, hardware, versions, and numerical agreement. Keep licensed timing logs local until sanitized. Establish an empirically supported memory envelope; do not promise every pooled model fits in 40 GB. If it fails, investigate narrower projections, appropriate disk-backed designs, and independently justified estimators before broadening support claims.

## Standard R package structure

Create the installable package in Phase 1 after the remaining design frontier is settled. Use the supplied book's principles and current R tooling rather than carrying forward its 2015 command examples.

```text
easyNIS/
  DESCRIPTION             authors, maintainer, license, dependencies, URLs
  NAMESPACE               generated exports/imports
  R/                      focused modules
  man/                    generated function/data documentation
  tests/testthat/         numerical and workflow tests
  tests/testthat.R
  data-raw/               deterministic synthetic-data/metadata generation
  inst/extdata/           invented fixtures and distributable metadata
  vignettes/              executable synthetic workflows
  inst/CITATION           package citation, later paper citation
  README.Rmd / README.md
  NEWS.md
  CONTRIBUTING.md
  LICENSE / LICENSE.md
  .github/workflows/      checks, coverage, documentation
  _pkgdown.yml
  .Rbuildignore
  docs/                   planning, methods evidence, decisions; excluded from build
  docs/references/local/  local-only reference book
```

Use `usethis`, `devtools`, `roxygen2`, `testthat` edition 3, `rcmdcheck`, and `pkgdown` as development tools. Use qualified dependency calls and documented exports; keep development/rendering dependencies in `Suggests` where practical. Decide the minimum R version by testing dependencies and CI rather than copying easyNRD's requirement. The local installation contains R 4.6.1.

Do not embed credentials, licensed records, machine-specific file paths, automatic package installation, or network retrieval in ordinary examples/checks. Run checks on a built source tarball to verify that required metadata/fixtures survive `.Rbuildignore`. Git ignores protect local files; they do not establish redistribution rights. [R package structure](https://r-pkgs.org/structure.html), [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html)

## Delivery sequence and release gates

| Phase | Deliverable | Dependency | Gate before proceeding |
|---|---|---|---|
| 0. Plan and agreements | Repository, references, glossary, decisions, backlog. | This planning session. | Shared scope and remaining frontier confirmed. |
| 1. Package foundations | Metadata, license, synthetic fixtures, first smoke workflow, R checks. | Maintainer metadata and API agreement. | Installs and passes checks with no licensed inputs. |
| 2. Registry and parquet import | Reviewed 2017–2022 schemas; local conversion inventory; joins and diagnostics. | Phase 1. | No unintended row multiplication; strings/keys/missing semantics verified. |
| 3. Harmonization and cohorts | Canonical variables, explicit code-set/slot policy, SQL/R parity. | Phase 2. | Documented meanings and cohort tests across each initial year. |
| 4. Survey and pooling | Full design, domain, weight/estimand controls. | Phase 3. | Numerical agreement for point estimates and SEs against independent reference. |
| 5. Models | Approved survey GLMs, diagnostics, missingness report. | Phase 4. | Coefficients, SEs, intervals, tests, exclusions verified. |
| 6. Tables and reporting | CSV/HTML/Word exports with disclosure checks and provenance. | Phases 4–5. | Suppression preserved across formats; reproducible synthetic end-to-end example. |
| 7. Private validation and beta | Full licensed 2017–2022 checks, 40 GB benchmarks, external user trial. | Phases 2–6. | Every claimed capability has evidence per year. |
| 8. Stable v1 and CRAN | Cross-platform checks, docs, release notes, tagged release, CRAN submission. | Phase 7. | Release checklist satisfied; submission is a separate release action. |
| 9. Coverage expansion | 2023, 2012–2016 including 2015, 1993–2011, then 1988–1992. | Stable core; new validation access. | Same per-year evidence gates; trend claims reviewed separately. |
| 10. JOSS submission | Comparison, adoption evidence, paper, archival release/DOI. | Mature release, actual research use, public development history. | Current JOSS criteria checked again before submission. |

Documentation and synthetic tests accompany each phase. Models and tables are v1 requirements, so a release that stops after import or survey construction is an internal alpha. Historical expansion can continue while collecting publication evidence; a paper must accurately describe the coverage of the archived version.

Suggested work split, subject to agreement: Saad coordinates API/maintainer/release work and the reproducible paper workflow; Ali reviews data definitions and independent statistical comparisons. Both review cohort, harmonization, survey, and disclosure changes. Build backend modules and docs in parallel only when their contracts are settled. Do not assign unreviewed methodological decisions to implementation convenience.

## Validation and evidence

Public CI uses entirely invented fixtures with deterministic generation and documented provenance. Tests must assert observed values and statistical results. Include malformed files, missing components, mixed years, identifier precision, duplicate keys, absent slots, valid negative values versus missing sentinels, missingness reasons, and unsupported-year requests.

Private licensed tests compare imported counts and selected summaries with official annual specifications and summary statistics. Compare survey estimates/models with independently constructed R and, where available, SAS or Stata reference analyses. Record reference script/version, years, estimand, weight, sample accounting, tolerances, and any discrepancy. HCUP aggregate tables may be rounded or have different definitions; document expected differences rather than forcing a false exact match.

Use separate support levels: target, metadata-audited, synthetic-validated, licensed-validated, release-supported. Also track import, harmonization, cohort, survey, model, and table capabilities individually. No year is supported today. Test the full workflow for each 2017–2022 year before promoting v1 support. Historical private validation access remains a later dependency.

Cross-platform CI should cover Windows, macOS, Linux, current R release, old release, and devel where the dependency stack permits. Keep fast tests on each change and larger synthetic/performance jobs separately. Coverage percentage is a diagnostic; critical methodological branches need meaningful tests even if overall coverage is high.

## Documentation and ease of use

Provide one executable synthetic quickstart plus vignettes for importing/parquet conversion limits, annual metadata, ICD cohorts, single-year/domain inference, pooled/trend estimands, models/missingness, publication tables/disclosure, large-data behavior, and analysis provenance. Function help needs inputs, output classes, assumptions, failure conditions, and runnable examples.

Have a colleague unfamiliar with easyNIS follow the quickstart without live coaching. Record completion, confusing steps, error messages, and time to first correct result. Use this feedback to reduce required concepts and improve wording. Expose detailed methods on request; keep novice defaults documented and statistical meaning visible.

## CRAN release checklist

- Accurate `DESCRIPTION`, maintainer contact, license, URLs, citation, and dependency declarations.
- All exported functions/data documented; examples and vignettes run without purchased data.
- A built tarball contains required files and excludes local books, licensed records, and private validation results.
- `R CMD check --as-cran` passes supported platforms; investigate notes and record justified exceptions.
- Numerical tests, component joins, model accounting, and disclosure exports pass.
- The year/capability matrix agrees with README, help, vignettes, and release notes.
- Versioned tag, changelog, migration notes, installation instructions, support process, and reproducibility metadata exist.
- Independent beta users complete the workflow; benchmark limitations are published.

Use the [current CRAN policy](https://cran.r-project.org/web/packages/policies.html) and [release guidance](https://r-pkgs.org/release.html) when releasing. CRAN acceptance is not a substitute for licensed-data or methods validation.

## Paper plan

Primary target: JOSS. Proposed contribution: a verified, era-aware NIS workflow combining import validation, cohort provenance, survey inference, models, and disclosure-aware tables. Establish the contribution through comparison and real use; avoid claiming to be the first HCUP package.

Prepare a comparison against manual HCUP loading plus survey analysis and relevant existing packages such as HCUPtools, touch, survey/srvyr, and gtsummary. Compare supported tasks/years, safeguards, reproducibility, correctness, memory, and user effort. Do not frame general-purpose packages as competitors for tasks they do not claim to perform.

Collect evidence from the beginning: public iterative commits, issues and reviewed PRs, tags/changelog, CI, contributions, at least one real research workflow, and user feedback. The current JOSS rules require more than six months of active public history and demonstrated research use. A repository created on October 8, 2026 would reach six months on April 8, 2027, but elapsed time alone does not establish eligibility. Recheck the rules when the software is ready. [JOSS submission guidance](https://joss.readthedocs.io/en/latest/submitting.html)

The paper should explain the need, state of the field, design/contribution, supported coverage, validation, use case, limitations, and maintenance. Keep an independently reproducible synthetic workflow public. Licensed research examples can publish permissible aggregate results and analysis code with instructions for authorized users, rather than redistributing records. Archive the reviewed release and obtain a DOI at the appropriate submission stage.

Maintain an AI-assistance record describing tools, versions when known, and scope. JOSS requires disclosure and human review of AI-assisted outputs. Saad and Ali own the design and validate the scientific claims. The R Journal is an alternative after CRAN release if a longer technical article better fits the contribution; its current guidance requires substantial, mature software, numerical tests, documentation, and a full-workflow vignette. [The R Journal submission guidance](https://journal.r-project.org/submissions.html)

## Immediate next work

1. Review the completed written plan and confirm shared understanding of the proposed contracts.
2. Obtain the public maintainer email, preferred author names/ORCIDs, and local validation file paths without publishing local paths or data.
3. Inventory the 2017–2022 parquet conversions and gather official annual schemas.
4. Create the package foundation, synthetic end-to-end fixture, and R CMD check CI.
5. Implement one 2022 parquet-to-cohort-to-survey-to-model-to-table workflow, then exercise the same contracts on each remaining initial year.

Detailed executable task acceptance criteria are in [BACKLOG.md](BACKLOG.md). Expansion requires additional historical validation access; it does not delay the initial 2017–2022 release once its full workflow passes.
