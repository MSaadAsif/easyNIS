# How published studies use the National Inpatient Sample

This review follows the analysis from cohort definition to public output. It
extends the [October 12-study review](2026-10-nis-literature-report.md) with a
larger sample and maps the work to the R package at **5dbbb40**. The counts below
describe methods reporting in the reviewed papers. The review extracted no
clinical estimates or comparisons of study outcomes.

## Search and coding

We searched [Europe PMC](https://europepmc.org/RestfulWebService) for
`SRC:MED AND OPEN_ACCESS:y AND (TITLE_ABS:"National Inpatient Sample" OR
TITLE_ABS:"Nationwide Inpatient Sample")`, adding each of three
`FIRST_PDATE` ranges (2016–2019, 2020–2022, 2023–27 November 2026) and one
of the following title filters per query. Words and phrases within each row
were joined with OR.

| Stratum | Title terms |
| --- | --- |
| Cardiology | cardiac, coronary, myocardial, aortic, heart, arrhythmia |
| Surgery | surgery, surgical, arthroplasty, spine, trauma |
| Neurology | stroke, neurologic, epilepsy, migraine, multiple sclerosis |
| Gastroenterology | pancreatitis, cirrhosis, gastrointestinal, colitis, liver |
| Obstetrics and pediatrics | pregnancy, obstetric, neonatal, pediatric, delivery |
| Oncology | cancer, oncology, malignancy, leukemia, lymphoma |
| Health services and disparities | disparities, insurance, health care costs, rural, socioeconomic |

For each of the 21 queries we retrieved up to 100 records sorted by citation
count (`sort=CITED desc`). Among records with a PMCID and DOI, we tried the
most cited first, then sorted the remainder by SHA-256 of
`easyNIS-2026-11:<PMID>`. We took three distinct studies with usable methods
per cell in the order above, oldest period first within each stratum. A study
could have fit several title strata. We assigned it to the first eligible cell
and skipped duplicates later. Full-text XML came from PMC EFetch and Europe
PMC. We screened for original studies analyzing NIS discharges and excluded
reviews, abstracts, studies confined to other HCUP databases, and studies that
only quoted NIS inputs. Study year refers to the discharge data, while the
sampling periods refer to first publication dates. The supplement to this
review adds deliberately selected examples for uncommon methods. Those
examples and agency reports are outside all 63-paper denominators.

We inspected the methods, relevant design and cohort statements, and table
and figure captions. We coded what a reader could reconstruct from the
accessible report. Keyword screening located candidate method statements and captions. We
checked the cohort and estimator descriptions against the accessible text.
We did not comprehensively inspect linked codebooks or analysis scripts. An empty field records absent or unclear
reporting in the material reviewed. A hospital variable described only as
available in NIS is insufficient to establish that it entered a model.
A code list without a slot rule leaves the slot unspecified. A software name,
generic survey language, or a statement that estimates are national gives
less evidence than an explicit description of weighting, stratification, and
clustering. Annual series, a test for trend, and an annual percent change
answer different questions and were kept distinct where the method was clear.

This is a stratified, open-full-text workflow sample. The title filters, one
citation-ranked selection per cell, time bins, retrieval requirements, and
equal allocation limit generalizability. The mix includes higher-visibility
specialty and general journals and journals serving narrower audiences. The
counts are unweighted proportions of documents, with no population-wide
prevalence claim or comparison of rates across eras. We did not independently
replicate data processing or re-review papers with a second coder.

## What to guard against

[Khera et al. (PMID 29183077)](https://pubmed.ncbi.nlm.nih.gov/29183077/)
audited seven practices in 120 NIS papers published in 2015–2016. Their
categories covered the unit of inference, inappropriate state, hospital and
physician analyses, nonspecific secondary diagnoses used as incident inpatient
events, survey variance, and changes in NIS structure. Their most common
flags involved design-based inference, attribution of secondary diagnoses to
the admission, and treating discharge records as distinct people. Their Europe PMC reference and cited-by lists led to their earlier
methods commentary and the 2026 follow-up. We used the HCUP Methods Series
and the agency publications below to verify the workflow recommendations. Our reporting screen uses a different selection and coding method.
The frequencies below describe what was or was not reported, with clearly
documented counterexamples called out separately.

- **Unit and inference.** Preserve the discharge as the analysis unit. One
  person can contribute multiple stays, including transfers. NIS covers
  inpatient stays, so national counts do not supply unique-person,
  longitudinal readmission, or outpatient denominators. Population rates need
  an external, age-, time-, and geography-aligned population denominator.
  Use a dataset designed and permitted for state, provider, or longitudinal
  hospital inference. Discharge comparisons by region, bed size, and teaching
  status are ordinary survey estimands. [HCUP NIS checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp)
- **Survey estimation and domains.** Begin with the sampled universe for the
  chosen years, use discharge weights and appropriate variance structure, and
  then restrict the survey domain. Retain information about hospital-years
  with zero qualifying rows. Ordinary IID tests, frequency-weighted GLMs, or
  standard errors from regressions on expanded pseudo-records are unsuitable
  for national design-based inference. NIS's 2012+ sampling draws discharges.
  HCUP's recommended variance computation uses hospital clustering and NIS
  strata. For pooled analyses use year-scoped design identifiers. A hospital-year
  cluster adjusts sampling variance. A random intercept adds a conditional
  outcome model and needs its own target, design and levels of weighting, and
  variance justification. A random intercept on an annual identifier cannot
  identify stable between-hospital differences or substitute for survey
  adjustment. [HCUP Methods Series 2015-09](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp)
  · [Variance addendum](https://hcup-us.ahrq.gov/reports/methods/MS2015-09%20Addendum.pdf)
- **Secondary diagnoses and temporal order.** A secondary diagnosis can be
  present at admission or occur later. Use appropriately timed procedure data,
  explicit complication definitions, or documented POA information where
  applicable. Distinguish a concurrent diagnosis from an incident event. A
  principal diagnosis can anchor the reason for admission. A secondary slot
  alone cannot establish incidence, sequence, or causal attribution. The
  problem persists wherever an association study labels co-recorded diagnoses
  as postoperative events without describing timing evidence. [Khera et al.](https://doi.org/10.1001/jama.2017.17653)
- **Redesign and coding.** Use `TRENDWT` for pre-2012 years in trends that
  span the redesign and `DISCWT` from 2012 onward. Treat the October 2015 ICD
  transition separately, document both code sets and their validity, and
  inspect discontinuities and partial-year denominators before pooling. The
  paper on STEMI with heart failure and diabetes describes the reverse
  weight assignment in its methods. The paper on IVUS/OCT-guided PCI
  documents the pre-2012 trend weight and separates the ICD periods within
  2015. [HCUP trend weights](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp)
  · [2015 NIS introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2015.jsp)
  · [PMID 35185613](https://pubmed.ncbi.nlm.nih.gov/35185613/)
  · [PMID 36852085](https://pubmed.ncbi.nlm.nih.gov/36852085/)
- **Propensity estimates.** Declare the target population and estimand, the
  treatment model, treatment and survey weights, trimming or matching rules,
  weighted balance, and variance approach. An unweighted matched sample
  analyzed as IID does not support a nationally representative effect estimate.
  It can target a narrower matched-sample contrast if the assumptions and
  uncertainty account for the design and matching. Multiplying supplied causal
  and survey weights changes the target of totals and does not in itself
  account for propensity estimation. Keep national counts on the original
  survey design. [Evaluation of propensity score methods for complex surveys](https://pubmed.ncbi.nlm.nih.gov/23855598/)
- **Disclosure.** Check raw discharge counts, the contributing hospitals, and
  whether a suppressed value can be recovered from totals, percentages, text
  or another panel. The nationwide DUA directs users to avoid publishing counts
  of 1–10. AHRQ also requires at least two contributing hospitals. An article's
  silence on suppression cannot establish a disclosure violation.
  [Nationwide DUA](https://hcup-us.ahrq.gov/team/NationwideDUA.pdf)
  · [HCUP NIS checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp)

HCUP's own publications show practical output patterns. Statistical Brief
#225 describes annual utilization and resource use over a redesign-spanning
period. Statistical Brief #277 defines a principal-diagnosis denominator,
excludes maternal and neonatal stays for its main tabulation, and summarizes
discharge counts, population rates, mean LOS and CCR-derived mean cost by
patient location. These serve as agency examples outside the article counts.
[HCUP Statistical Brief #225](https://hcup-us.ahrq.gov/reports/statbriefs/sb225-Inpatient-US-Stays-Trends.jsp)
· [HCUP Statistical Brief #277](https://hcup-us.ahrq.gov/reports/statbriefs/sb277-Top-Reasons-Hospital-Stays-2018.jsp)

## What the methods report

Most papers need one dependable path from ICD-coded eligibility to a
survey-weighted cohort table and a regression on the same design. The
distinctive NIS work is establishing the domain, tracking year-specific code
and field validity, carrying denominators through the model, and protecting
released cells. The sample offers a weaker case for new statistical fitters.

| Pattern in the coded methods or captions | Papers out of 63 |
| --- | ---: |
| Definite slot statement for at least one defining component | 29 |
| Named Elixhauser or Charlson method | 28 |
| Hospital characteristics in the methods | 44 |
| In-hospital death | 43 |
| LOS | 42 |
| Charges or estimated costs | 38 |
| Coded adverse outcomes or complications | 29 |
| Discharge destination or disposition | 12 |
| Explicit discharge weighting | 40 |
| Explicit weighting, clustering and stratification together | 8 |
| Other survey procedure or variance detail | 16 |
| Explicitly unweighted main analysis | 2 |
| Temporal analysis or time plot | 31 |
| Flow diagram identified in the accessible paper or referenced supplement | 15 |
| Explicit small-cell language | 5 |

Counts can overlap. The NIS-specific estimators in this sample were weighted
totals, proportions, means, population rates and survey-model contrasts.
Many papers also named conventional tests. A statement that an analysis used
a chi-square test or logistic regression gives no assurance that the design
was carried into that test or model. Rao–Scott, adjusted Wald and
Taylor-linearized examples provide clearer porting targets.
SPSS (23), SAS (20), Stata (15) and R (7) recur.
A single study can appear in multiple software counts. Package examples
should translate the estimand and design rather than follow vendor syntax.

### Persistence of the Khera flags

Dhingra and colleagues implemented a probabilistic follow-up across two
publication periods. Their most recent window was July 2021 through June
2023. These are estimates of methodological reporting and practice, with
conditional denominators where the practice applies. The older and
newer columns come from the two published audits. They establish context
for our different workflow sample and contain no estimates of clinical outcomes.
[Khera et al., PMID 29183077](https://pubmed.ncbi.nlm.nih.gov/29183077/)
· [Dhingra et al., PMID 41591780](https://pubmed.ncbi.nlm.nih.gov/41591780/)

| Khera flag | 2015–2016 audit, weighted estimate | 2021–2023 follow-up, weighted estimate |
| --- | ---: | ---: |
| Discharges treated as unique patients | 40.4% | 43.2% |
| State-level inference | 7.1% | 2.2% |
| Inappropriate hospital volumes | 8.2% among volume analyses | No phase-2 instances observed |
| Physician-level volumes | 2.9% | No phase-2 instances observed |
| Nonspecific secondary codes taken as in-hospital events | 54.4% | 31.1% |
| Complex design omitted | 68.3% | 55.7% |
| Redesign omitted among eligible analyses | 79.7% | 74.7% |

The follow-up used a different publication window and its supplementary
criteria govern its denominators. Zero observations in the screened sample
give limited evidence about rare practices. In our sample, explicit design
detail was sparse even when weighting was reported. Among 23
redesign-spanning papers tagged for temporal reporting, eight gave an
explicit description of the pre-2012 adjustment and one described the
reversed assignment. The remaining papers included several with only
generic weight language and at least one intentionally unweighted analysis.
A reader cannot infer implementation from those descriptions. We did not
independently estimate every Khera flag from the 63 articles.

For example, the LVAD stroke paper identifies stroke through DX codes
during the same stay as the implant PR. Those codes and their position do
not establish that stroke followed implantation. Two separate
cohorts explicitly reported unweighted main analyses and framed their
targets as associations in their analytic samples. Their model claims
still depend on how the record-level dependence and target population
were handled. [PMID 32035527](https://pubmed.ncbi.nlm.nih.gov/32035527/)
· [PMID 33447777](https://pubmed.ncbi.nlm.nih.gov/33447777/)
· [PMID 40296087](https://pubmed.ncbi.nlm.nih.gov/40296087/)

## Workflow coverage at 5dbbb40

Counts refer to the ledger. Rows can overlap. The linked studies give examples
of the decisions an analyst needs to make. "Covered" means a public package
entry point or a direct handoff to a design-aware R function. "Partial" means
the key operation exists and the analyst still has to assemble or validate
the workflow. An absent estimator can still be used with a suitable external
method.

| Workflow step and frequency | Current coverage | Smallest change to make correct use easier |
| --- | --- | --- |
| **Open and join**. All 63 used NIS. Hospital characteristics appeared in 44 methods records, and 12 specified a CCR calculation. | **Covered** for supported Core layouts and companion linkage. `nis_convert()`, `nis_open()`, and `nis_join_companion()` handle lazy projections and annual links. `nis_join_companion()` accepts Hospital, Severity and DX/PR Groups, with different keys. `nis_cost()` consumes the CCR column. | Document an ordinary 2016+ Core-to-Hospital-and-cost path. Show that a companion join cannot multiply rows and that missing links remain visible. Keep provider identifiers and hospital totals out of discharge-level examples. |
| **Codes and positions**. 34 used ICD-9 only, 17 ICD-10 only, 11 both explicitly and one used pre- and post-transition years with coding details in its appendix. 29 recorded a definite slot policy for at least one cohort component. Eight used or referenced CCS in the analytic definition, and one reported CCSR. | **Covered** for explicitly positioned ICD flags and ICD-10 CCSR with `nis_flag_dx()`, `nis_flag_dx_position()`, `nis_flag_pr()`, `nis_add_ccsr()`, `nis_ccsr_codes()`. **Partial** for mixed ICD definitions, dates and versioning through `nis_audit_code_transition()`. Pre-2012 design and native legacy CCS classification are gaps. Use historic supplied companion fields where applicable. | Show one named eligibility flag combining separately supplied ICD-9 and ICD-10 definitions on each applicable quarter. Put the diagnosis/procedure role, slot, system, version and valid dates beside the codes. Keep clinical code definitions in the study. |
| **Exclusions and attrition**. 28 short codes below record a substantive restriction or missing-value handling beyond the anchor, and 15 papers show a flow caption or equivalent. 20 methods records explicitly discuss missingness. | **Partial**. `nis_attrition()` gives sequential raw and weighted counts, optionally by year. `nis_design()` separately records invalid design rows. `nis_dx_sensitivity()` supplies an initial position sensitivity check and comparison of definitions. | Reuse named predicates between the attrition sequence and final domain. Report design exclusions, clinical exclusions and model complete cases with separate denominators. Preserve unknown categories and distinguish missing flags from false flags. |
| **Survey descriptives and domains**. 40 papers explicitly reported applying weights. Eight of those specified weights, strata and clusters together. Another 16 reported a survey procedure, linearization or partial design detail. 41 papers had a baseline/characteristics table. | **Covered** by `nis_design()` plus `srvyr`, `survey` and `gtsummary::tbl_svysummary()`. **Partial** for the experimental placeholder representation, fit-specific complete cases and a consistent published design record. | Add a methods block emitted by the starter study containing year-scoped keys, weight and scaling, universe years, cohort and analysis domains, invalid fields, unweighted and weighted denominators, design df, variance method, and package versions. Validate rare-domain SEs and df against the complete sample. |
| **Comorbidity**. 28 named a Charlson or Elixhauser method, including 17 Elixhauser and 12 Charlson, with one study using both. Other studies used individual coded conditions, APR-DRG, a frailty measure or an obstetric index. | **Partial**. `nis_comorbidity()` has pinned refined AHRQ Elixhauser releases, Quan variants, Deyo and legacy definitions, with release-specific limitations. It can use supplied POA. Missing POA slots can trigger a warning and a present-at-admission assumption. Historic scores and diagnosis-related group exclusions require checking. `nis_join_companion()` can expose supplied HCUP measures. | Make the method and POA coverage prominent in the study report. Record score versus indicators and any exclusions such as cancer, hypertension or the exposure itself. Show how to bring in a supplied HCUP field before attempting exact historical reproduction. |
| **In-hospital outcomes**. Death, LOS, money fields, coded adverse events and disposition are recurring. Their methods mentions are tabulated above. | **Covered** for standard Core fields by `nis_outcomes()` and `nis_label()`. **Partial** for event timing: `nis_flag_pr_timing()` and `nis_prday_completeness()` expose procedure days and their gaps. Code flaggers define documented conditions. | Keep death and disposition separate. Preserve valid zero-day stays and unknown destination. Require a named temporal rule for labels such as “new” or “postoperative,” or describe a concurrent condition. Document what happens to death and transfers in LOS or disposition models. |
| **Charges and estimated costs**. 38 methods records mention charge or cost work, 12 mention CCR and 17 mention price adjustment. Definitions include log charge, cost per stay and aggregate utilization. | **Partial** via `nis_cost()`, `nis_cost_provenance()` and the manual CCR input. Core field rules and CPI-U support are explicit. Several papers use medical CPI or a health expenditure deflator. | Start with a keyed CCR recipe and small cost provenance table before accepting arbitrary inflation series. Record which price series, base year, charge field and missing-CCR treatment were actually used. |
| **Regression and adjusted results**. 48 reported logistic models including propensity models, 12 linear, five Poisson and three negative binomial. Two reported multinomial, and one ordinal. | **Covered** for prespecified design-based GLMs via `nis_design()` → `survey::svyglm()`. Use quasi-binomial or quasi-Poisson where appropriate, with identity and log links for different estimands. `survey::svyolr()` supports ordinal outcomes. **Partial** for translated natural-scale estimates and run diagnostics. No easyNIS multinomial, quantile regression or estimated-dispersion negative binomial fitter. | Add a binomial and an LOS or cost example to the existing article. Distinguish a ratio of means from a mean difference and a conditional quantile from a weighted descriptive median. Retain the model frame denominator and the adjustment set. Offer one reference recipe per supported estimand and keep specialized fitting in the R survey ecosystem. |
| **Trends**. 31 reported a temporal analysis or time plot, with 25 time-plot captions. Methods included yearly estimates, time terms and year-by-group interactions, ordered trend tests, APC and segmented analysis in the targeted examples. | **Partial**. `nis_annual_totals()` handles national discharge totals and uncertainty for complete years in the supported era. A corresponding `nis_design()` supports rates and means via `srvyr`. Pre-2012 designs, changes in code validity, population denominators and trend modeling require additional work. | Put year, quarter coverage, era, denominator, estimate, SE/CI and disclosure inputs in the same annual results table. Demonstrate pooled total versus average annual total versus annual estimates. Export that series to Joinpoint or a time-series tool, recording weights and the time model. |
| **Adjusted comparisons and policy analyses**. Five reported propensity matching. One used IPTW as a sensitivity analysis and another used propensity weighting for DiD. Overlap weights appear in the targeted examples. | **Partial**. Experimental `nis_reweight()` combines analyst-supplied positive weights with the survey design and preserves hospital-year placeholders. It does not fit the propensity model, create matches, estimate balance or propagate propensity-estimation uncertainty. | Provide a documented weighted comparison with a declared estimand, weighted balance, positivity, and a reference variance calculation. Keep match selection and its uncertainty external until a design-compatible worked example exists. |
| **Display, disclosure and export**. 60 had an extractable table, 47 a figure, 31 a modeled comparison table, and five disclosed a small-cell rule or restriction. | **Partial** via `nis_cell_counts()`, `nis_suppress()`, `nis_write_cohort()` for private cohort handoff and `nis_new_study()` for the private Quarto workflow. General complementary suppression across related tables and figures needs manual review. | Reuse the same grouped estimates and denominators for the table, figure and narrative. Mask before formatting, retain a private review record and prove suppressed cells cannot be recovered through the demonstrated margins. Render the final study using invented data. |

The regression gap is mostly documentation for ordinary models. Design-based
logistic, linear and log-link fits can share the same survey construction.
A Poisson model for a binary outcome with design-based standard errors targets
a risk ratio under its mean model. A Poisson model for LOS targets a mean
ratio or difference according to its link and contrast. For sparse count
patterns or overdispersion, check model fit and distinguish quasi-Poisson
variance from a full negative binomial model. A weighted median via
`survey::svyquantile()` summarizes a marginal distribution. It does not fit
a conditional quantile regression. For continuous outcomes with zeros,
explain the treatment of zero before applying a log or gamma model.
For multinomial or ordinal endpoints, make the ordering and reference category
explicit. Discharge to home, transfer and death typically do not share an
unambiguous ordering.

### Targeted methods outside the 63-paper sample

| Study | Method and implication |
| --- | --- |
| [Rubin et al., DOI 10.1111/jgs.17189](https://doi.org/10.1111/jgs.17189) | ICD-9 procedures, redesign weights, age-specific Census denominators and annual survey SEs precede log-linear Joinpoint and AAPC. Demonstrates the exchange format for specialized trend software. |
| [Main et al., PMID 35900764](https://pubmed.ncbi.nlm.nih.gov/35900764/) | AHRQ coauthored delivery-complication study fits quarterly segmented level and slope terms at the 2015 ICD transition, with annual plots and Stata survey estimates. Coding changes can be the interruption under study. |
| [Endocarditis, myocarditis and pericarditis ITS](https://doi.org/10.1007/s44203-025-00008-9) | Monthly segmented comparison around the pandemic in 2018–2020 NIS. Record the interruption definition and assess seasonality, autocorrelation and parallel shocks before attributing changes to policy. |
| [Young-adult intracerebral hemorrhage](https://doi.org/10.3390/jcm14238475) | Principal ICD-10 hemorrhage, survey logistic mortality, negative binomial LOS, gamma-log charges. Reports survey-weighted median regression as sensitivity analysis. Model family and variance need to be checked for the exact fit. |
| [AF and prostate cancer, PMID 38638883](https://pubmed.ncbi.nlm.nih.gov/38638883/) | Logistic propensity model plus overlap weighting and standardized mean differences in sensitivity analysis. Useful as a balance and target-population example. The propensity method alone does not establish population variance. |
| [Hospital and regional effects on LOS](https://doi.org/10.1080/24725579.2026.2645699) | Reports an additive mixed model for a subset of 2019 NIS discharges, decomposing hospital and regional variation. A cross-sectional hospital-level model is a separate conditional estimand. It cannot be read as an estimate of stable hospital rankings or as a substitute for sampling design. |
| [Berger et al., PMID 37411020](https://pubmed.ncbi.nlm.nih.gov/37411020/) | Demographic decomposition compares changes in the age distribution of delivery admissions and changes in age-specific severe maternal morbidity rates between two periods. A descriptive decomposition needs valid stratum estimates and uncertainty for the component contrasts. |
| [Racial differences in hospital death for AF, PMID 31008458](https://pubmed.ncbi.nlm.nih.gov/31008458/) | Hospital-clustered GEE, time-by-race interaction and decomposition using hospital racial composition in 2001–2012. This is a within/across-hospital model. It is distinct from an Oaxaca–Blinder model and does not demonstrate portable hospital identifiers. |

### Ranked implementation briefs

Use the [contributor qualification](../../CONTRIBUTING.md#verify-a-change) for
each brief. Retain the fixture inputs, command, platform, transcript and
expected versus observed outputs. Effort estimates include reference
comparisons and documentation.

| Rank | Ownership and deliverable | Proof required | Effort and payoff |
| --- | --- | --- | --- |
| 1 | **Design and model reporting**. `R/design.R`, `R/design-sample.R`, `R/cohort-design.R`, `R/study-model.R`, `vignettes/articles/design-validation.Rmd`. Extend the existing validation matrix before changing the design. Put dataset years, exclusions, weights and actual model denominator in the starter study. | Compare totals, ratios, coefficients, SEs, df and CIs against a full-data `survey` reference for a rare domain, nested domain, missing model values, singleton strata and repeated hospital IDs across years. Exercise a prefiltered input to show the error it induces. | 3–5 days. Highest payoff for national inference. |
| 2 | **Shared eligibility and era record**. `R/attrition.R`, `R/code-flags.R`, `R/code-audit.R`, `vignettes/articles/cohorts.Rmd`, `vignettes/articles/code-transitions.Rmd`. Start with one worked example sharing named criteria before adding any new public API. | Final attrition count equals the model's eligibility denominator after stated design exclusions. Exercise 2015 Q3/Q4, principal versus any slot, overlapping codes and missing predicates using expected hand counts and the lazy Parquet entry point. | 2–3 days. Applies to nearly every cohort and exposes changes that otherwise silently affect trends. |
| 3 | **A report with traceable denominators**. `R/cell-counts.R`, `R/disclosure-policy.R`, `R/study-disclosure.R`, `inst/templates/nis-study/`, `vignettes/articles/disclosure.Rmd`. Carry support counts through a baseline table, model table and annual plot. | Render an invented report with small, single-hospital, and large cells. Check that margins and shared outputs cannot recover the masked example. Exercise a group present only in a subset of years. | 2–4 days. High payoff and applies to every public output. |
| 4 | **Year and quarter series for rates and means**. `R/trends.R`, `vignettes/articles/trends.Rmd`. Build on `nis_annual_totals()` and the survey design. Add one externally denominated series and a separate model example. | Verify annual and pooled quantities by hand and against `survey`. Show scaling of numerator and SE by a fixed external denominator, rejection of gaps, and explicit handling of a 2015 split. No claims of pre-2012 package support. | 2–4 days. High for multiyear studies. |
| 5 | **Companion and cost provenance**. `R/open-companion.R`, `R/cost.R`, `vignettes/articles/costs.Rmd`, `vignettes/articles/year-notes.Rmd`. Show one year-keyed CCR input and how it differs from Hospital and Severity links. | Invent year-reused hospital IDs, a duplicate key and an unmatched year. Compare charge × ratio × price factor by hand and ensure links stay one-to-one on the companion side. | 2–3 days. Frequent for resource outcomes and hospital adjustment. |
| 6 | **Comorbidity and outcome timing provenance**. `R/comorbidity-methods.R`, `R/comorbidity.R`, `R/prday-completeness.R`, `vignettes/articles/comorbidity.Rmd`, `vignettes/articles/outcomes.Rmd`. Show pinned method, POA eligibility and alternative outcome definitions. | Verify codes spanning eras, missing POA slots, exempt diagnoses and version-specific differences against known reference cases. Demonstrate a same-day PR versus missing PRDAY and a secondary diagnosis whose time remains unknown. | 2–4 days. Meaningful for risk adjustment and complication coding. |
| 7 | **Worked design-based models and reweighting**. `vignettes/articles/descriptives-models.Rmd`, `vignettes/articles/survey-design.Rmd`, `R/reweight.R` only if checks reveal a defect. Demonstrate survey logistic plus a mean contrast and show a weighted sensitivity example. | Retain model frames, original and transformed estimands, balance summaries, and variance comparison against a full-data reference. Verify ordinary national totals from original survey weights. | 2–4 days. Improves frequent model reporting while keeping niche fitting in specialist tools. |

## Paper-level methods ledger

Each row links a PMID. Data eras refer to the NIS analysis actually reported.
`P` marks a principal diagnosis or procedure, `S` a secondary diagnosis,
`P/S` distinct principal and secondary roles, and `A` an explicit
any-position rule. `A/P` indicates different slot rules for different
diagnoses and `P/A` indicates principal and any-position components. `?` indicates an
ambiguous description and `—` indicates no confidently assigned value.
DX and PR denote diagnoses and procedures. `W` means explicit application
of survey weights, `WSC` explicit mention of weights, strata and clusters
in the analysis, and `V` a survey procedure or variance detail short of that
complete statement. `TW` marks the stated pre-2012 trend-weight adjustment,
and `U` an explicit unweighted main analysis. A figure tag comes from the
full-text XML or a documented supplement reference. The outcome and
comorbidity tags describe assessed or described analytic variables, with
overlap across categories. They do not establish correctness or complete
reproducibility.

### Cardiology

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Chaker Z, 2017 (PMID 28935681)](https://pubmed.ncbi.nlm.nih.gov/28935681/)<br>J Am Heart Assoc | 2003–14 · 9 | — | Aortic stenosis DX and AVR PR. Concomitant surgery excluded for matched comparison. Race multiply imputed. | 1:1 nearest-neighbor matching and paired comparisons; mortality on procedure day via timing<br>hospital covariates, death, LOS, charges, cost, CCR, disposition, coded events, missingness addressed | W, TW | table, baseline, figure, flow, time plot, SPSS, R |
| [Desai R, 2017 (PMID 29312837)](https://pubmed.ncbi.nlm.nih.gov/29312837/)<br>Cureus | 2010–14 · 9 | — | AMI CCS 100, ages 11–70. ICD marijuana history or dependence. | Logistic; separate external marijuana-user denominator for trend figure<br>hospital covariates, death, LOS, charges, CCS | W | table, baseline, model table, figure, time plot, forest, SPSS |
| [Goyal P, 2017 (PMID 28356281)](https://pubmed.ncbi.nlm.nih.gov/28356281/)<br>J Am Heart Assoc | 2008–12 · 9 | — | Adult acute diastolic HF, exclude concurrent systolic HF and missing demographics. Sex and race groups. | AHRQ Elixhauser measures and weighted score; Taylor SEs; age-cutoff sensitivity<br>Elixhauser, hospital covariates, death, missingness addressed | W, V | table, baseline, model table, figure, SPSS |
| [Vallabhajosyula S, 2020 (PMID 32239806)](https://pubmed.ncbi.nlm.nih.gov/32239806/)<br>ESC Heart Fail | 2000–14 · 9 | ? | AMI and cardiogenic shock with pulmonary artery or right heart catheterization. Exclude missing death and cardiac surgery. | Deyo; PRDAY for concomitant interventions; matching and logistic trends<br>Charlson, hospital covariates, death, LOS, cost, disposition | W, V, TW | table, baseline, model table, figure, time plot, SPSS |
| [Ali B, 2022 (PMID 35185613)](https://pubmed.ncbi.nlm.nih.gov/35185613/)<br>Front Physiol | 2005–17 · 9+10 | P | Principal STEMI with HF and diabetes. Separate reduced and preserved EF codes. | Logistic and annual summaries; states reversed DISCWT/TRENDWT assignment<br>Elixhauser, death, LOS, charges, cost, price adjustment | W, TW reversed | table, baseline, model table, figure, flow, SPSS |
| [Levinson DJ, 2020 (PMID 33447777)](https://pubmed.ncbi.nlm.nih.gov/33447777/)<br>Int J Cardiol Hypertens | 2010–15 · 9 | A | Any-position SLE 710.0 with non-SLE matched controls. Exclude malignancy and selected immune conditions. | CCS comorbidities; conditional regression; ages stratified<br>hospital covariates, charges, CCS, missingness addressed | U, small cells | table, figure, Stata |
| [Park DY, 2023 (PMID 36852085)](https://pubmed.ncbi.nlm.nih.gov/36852085/)<br>Int J Cardiol Heart Vasc | 2008–19 · 9+10 | P | Principal MI plus PCI, then IVUS or OCT by procedure code. Code sets switch at 2015 Q4. | Cochran–Armitage and linear trends; Poisson for mortality trend; national weights by era<br>hospital covariates, death, LOS, charges, cost, CCR, price adjustment | W, V, TW | table, figure, time plot, SAS |
| [Shabtai R, 2025 (PMID 40277808)](https://pubmed.ncbi.nlm.nih.gov/40277808/)<br>Diseases | 2016–19 · 10 | — | MI admissions staged by coded CKM conditions. Exclude missing age, sex, admission data or death. | Logistic for mortality and coded MACCE components<br>hospital covariates, death, missingness addressed | W | table, baseline, figure, flow, SPSS |
| [Mondal A, 2024 (PMID 38390863)](https://pubmed.ncbi.nlm.nih.gov/38390863/)<br>Med Sci (Basel) | 2019 · 10 | — | Ages 65+ with coded cardiovascular risk factors. Exclude documented tobacco use; cannabis F12.90. | Complex-sample logistic for MACCE; adjusted for hospital region and teaching/location<br>hospital covariates, coded events | W, V | table, baseline, model table, SPSS |

### Surgery

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Alqahtani F, 2017 (PMID 29273638)](https://pubmed.ncbi.nlm.nih.gov/29273638/)<br>J Am Heart Assoc | 2003–14 · 9 | — | Adults with tricuspid repair or replacement PR. Exclude redo, congenital and other selected operations. | Mann–Kendall trend; compares isolated with concomitant operations<br>death, LOS, cost, price adjustment | W | table, baseline, figure, flow, time plot, SPSS |
| [Dixit A, 2018 (PMID 30132086)](https://pubmed.ncbi.nlm.nih.gov/30132086/)<br>J Orthop Traumatol | 1998–2013 · 9 | P | Principal open proximal humerus fracture plus ORIF or arthroplasty. Exclude multitrauma and pathological fracture. | Deyo score; logistic for complication and dichotomized LOS and charges<br>Charlson, death, LOS, charges, cost, coded events | — | table, baseline, model table, SPSS |
| [Kandil A, 2016 (PMID 27186059)](https://pubmed.ncbi.nlm.nih.gov/27186059/)<br>Int J Shoulder Surg | 1998–2011 · 9 | — | Shoulder arthroplasty PR 81.80; transfusion codes distinguish allogeneic and autologous. | Charlson–Deyo and individual conditions; logistic<br>Charlson, LOS, charges | — | table, figure, time plot, SPSS |
| [Farley KX, 2021 (PMID 34278185)](https://pubmed.ncbi.nlm.nih.gov/34278185/)<br>JB JS Open Access | 1988–2017 · mixed years | — | Arthroplasty volume combined with Census and CDC life tables. Exclude revisions from prevalence accumulation. | Counting model for prevalent implants; separately tabulates revision volumes and costs<br>cost | — | table, figure, SPSS |
| [Al Jammal OM, 2022 (PMID 35356929)](https://pubmed.ncbi.nlm.nih.gov/35356929/)<br>Medicine (Baltimore) | 2010–14 · 9 | P | Principal lumbar degenerative disease, then decompression or fusion PR subgroups. | Poisson for receipt and surgical complications; Charlson and individual diagnoses<br>Charlson, hospital covariates, death, coded events | — | table, baseline, model table, Stata, R |
| [Kim KM, 2021 (PMID 34406402)](https://pubmed.ncbi.nlm.nih.gov/34406402/)<br>JAMA Netw Open | 2004 Q4–2017 Q3 · 9+10 | — | Principal procedure selects intervention and control surgeries. Exclude obstetric/neonatal stays, selected procedures and missing data. | Weighted DiD with balance and placebo checks; linear probability, log cost, NB LOS; modified Elixhauser indicators<br>Elixhauser, hospital covariates, death, LOS, charges, cost, CCR, price adjustment, coded events, POA mentioned, missingness addressed | W, V | table, baseline, figure, flow, Stata |
| [Wright JD, 2023 (PMID 37610753)](https://pubmed.ncbi.nlm.nih.gov/37610753/)<br>JAMA Netw Open | 2016–20 · 10 | — | Gender-related ICD DX plus procedure groups, NIS inpatient and NASS outpatient. Retain unknown covariates. | Weighted counts and series by procedure and age; grouped Elixhauser score<br>Elixhauser, hospital covariates, missingness addressed | W | table, baseline, figure, time plot, SAS |
| [Li J, 2025 (PMID 40296087)](https://pubmed.ncbi.nlm.nih.gov/40296087/)<br>BMC Surg | 2005–14 · 9 | — | Primary knee arthroplasty PR 81.54 and urinary retention codes. Exclude preoperative retention and missing data. | Explicit unweighted analysis; stepwise logistic; Charlson and Elixhauser<br>Elixhauser, Charlson, hospital covariates, death, LOS, charges, cost, coded events, missingness addressed | U | table, baseline, model table, figure, flow, R |
| [Huang L, 2025 (PMID 39837854)](https://pubmed.ncbi.nlm.nih.gov/39837854/)<br>Sci Rep | 2010–19 · 9+10 | P | Colectomy PR plus principal malignancy. Exclude <18 years and incomplete records. | Logistic for coded postoperative pulmonary complications; annual estimates<br>hospital covariates, death, LOS, cost, coded events | — | table, baseline, model table, figure, flow, SPSS |

### Neurology

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Ramirez L, 2016 (PMID 27169548)](https://pubmed.ncbi.nlm.nih.gov/27169548/)<br>J Am Heart Assoc | 2000–10 · 9 | P | Principal acute ischemic stroke, ages 25+. ICD code list in text. | SAS SURVEYMEANS; civilian population denominators and direct age standardization | W, V | table, baseline, model table, figure, SAS |
| [Singh T, 2017 (PMID 28818864)](https://pubmed.ncbi.nlm.nih.gov/28818864/)<br>Stroke | 2010–12 · 9 | A/P | Any-slot ischemic and principal hemorrhagic stroke DX; exclude trauma and rehabilitation stays. Palliative V66.7 and life-sustaining PR. | Logistic and discharge-timing analysis; missing-data and transfer interpretation<br>hospital covariates, death, LOS, charges, disposition, DRG, missingness addressed | — | table, model table, figure, Stata |
| [Thakkar S, 2019 (PMID 32035527)](https://pubmed.ncbi.nlm.nih.gov/32035527/)<br>Indian Heart J | 2009–2015 Q3 · 9 | — | Adult LVAD PR 37.66 plus ischemic or hemorrhagic stroke codes. | Logistic and trends; same-stay stroke identification without longitudinal linkage<br>death, LOS, coded events | — | figure, time plot, SAS |
| [Miller EC, 2020 (PMID 31973601)](https://pubmed.ncbi.nlm.nih.gov/31973601/)<br>J Am Heart Assoc | 1998–2014 · 9 | — | Delivery codes, stroke codes and maternal hypertension subgroups. Exclude hypertension from obstetric comorbidity index. | Poisson and interaction; excludes missing race; suppresses small cells<br>hospital covariates, missingness addressed | W, V, small cells | table, baseline, model table, SAS |
| [Haddadin F, 2021 (PMID 33850581)](https://pubmed.ncbi.nlm.nih.gov/33850581/)<br>J Arrhythm | 2016 · 10 | P | Adult AF and gout subgroups; principal stroke codes define the outcome. | Adjusted logistic; coded stroke called new, timing requires separate evidence<br>death, LOS, disposition, coded events | — | table, model table, Stata |
| [Chu KM, 2021 (PMID 33823605)](https://pubmed.ncbi.nlm.nih.gov/33823605/)<br>J Am Heart Assoc | 2006–2015 Q3 · 9 | P | Principal adult ischemic stroke with comfort care V66.7, thrombolysis and thrombectomy categories. | Ordinal disposition, logistic mortality, count LOS and cost models; Charlson and APR-DRG<br>Charlson, hospital covariates, death, LOS, charges, cost, CCR, price adjustment, disposition, DRG | W, V, TW | table, baseline, figure, time plot, Stata |
| [Rai AT, 2026 (PMID 40010850)](https://pubmed.ncbi.nlm.nih.gov/40010850/)<br>J Neurointerv Surg | through 2022 · 10 | P/A | Principal chronic subdural hematoma and any eligible PR. Uses NIS admission totals through 2022 and Medicare procedural data through 2023. | Annual national volume projections; check source denominators before porting<br>DRG | — | table, figure, time plot |
| [Kwok CS, 2024 (PMID 39057633)](https://pubmed.ncbi.nlm.nih.gov/39057633/)<br>J Cardiovasc Dev Dis | 2016–20 · 10 | P | Principal ischemic stroke I63, PFO and modified RoPE score using available DX. | Logistic; coded neurologic severity proxies<br>hospital covariates | — | table, model table, figure, Stata |
| [Desai R, 2023 (PMID 37240952)](https://pubmed.ncbi.nlm.nih.gov/37240952/)<br>J Pers Med | 2019 · 10 | — | Ages 65+ with OSA and prior stroke/TIA history codes. Exclude missing demographic and comorbidity data. | Complex-sample logistic; coded history plus diagnosis, no linked recurrence<br>death, coded events, missingness addressed | W, V, small cells | table, baseline, model table, figure, flow, SPSS |

### Gastroenterology

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Desai AP, 2019 (PMID 31343469)](https://pubmed.ncbi.nlm.nih.gov/31343469/)<br>Clin Transl Gastroenterol | 2008–14 · 9 | A | Adult cirrhosis in principal or secondary DX. Compare principal, decompensated and other cirrhosis stays. | NB resource models; Elixhauser; CCR plus inflation<br>Elixhauser, hospital covariates, death, LOS, charges, cost, CCR, price adjustment | W | table, baseline, model table, figure, SAS, R |
| [Araujo L, 2017 (PMID 28865456)](https://pubmed.ncbi.nlm.nih.gov/28865456/)<br>J Cardiothorac Surg | 2002–10 · 9 | — | Age 40+ with principal elective bypass or valve PR; coded liver dysfunction. | Matched controls; compare perioperative outcomes and CCR costs<br>LOS, charges, cost, CCR, price adjustment, coded events | — | figure, time plot, SAS |
| [Simons-Linares CR, 2019 (PMID 30762737)](https://pubmed.ncbi.nlm.nih.gov/30762737/)<br>Medicine (Baltimore) | 2003–13 · 9 | — | Acute pancreatitis with or without ketoacidosis and hypertriglyceridemia. | Survey procedures; logistic and linear models; Charlson and resource outcomes<br>Charlson, hospital covariates, death, LOS, charges, price adjustment | W, V | table, figure, time plot, SAS |
| [Hirode G, 2020 (PMID 32239220)](https://pubmed.ncbi.nlm.nih.gov/32239220/)<br>JAMA Netw Open | 2012–16 · 9+10 | P/S | CLD principal or a qualifying principal complication plus secondary CLD. Separate 2015 quarters by system. | Poisson mortality risk and linear models; CCR costs; Elixhauser<br>Elixhauser, hospital covariates, death, charges, cost, CCR, price adjustment, missingness addressed | W | table, baseline, figure, time plot, Stata |
| [Sohal A, 2023 (PMID 36593805)](https://pubmed.ncbi.nlm.nih.gov/36593805/)<br>Ann Gastroenterol | 2016–19 · 10 | — | Adult chronic pancreatitis DX; exclude missing vital status and demographic variables. | Frailty risk score and Charlson; adjusted logistic; LOS and charges<br>Charlson, hospital covariates, death, LOS, charges | W | table, baseline, model table, figure, flow, Stata |
| [Rim D, 2021 (PMID 34306896)](https://pubmed.ncbi.nlm.nih.gov/34306896/)<br>Cureus | 2014 · 9 | — | Adult acute pancreatitis with/without recorded SLE; omit rare candidate endpoints. | Elixhauser index; logistic and LOS comparison; multiple coded events<br>Elixhauser, death, LOS, coded events | — | table, baseline, model table, SPSS |
| [Nephew LD, 2023 (PMID 37471085)](https://pubmed.ncbi.nlm.nih.gov/37471085/)<br>JAMA Netw Open | 2009–18 · 9+10 | A | At least one cirrhosis code; compare receipt of procedures by race. Exclude invalid or missing race. | Survey trend weights; logistic and standardized procedure-use trends; Elixhauser<br>Elixhauser, hospital covariates, death | W, TW | table, baseline, figure, flow, time plot, SAS |
| [Teddy TA, 2026 (PMID 42367458)](https://pubmed.ncbi.nlm.nih.gov/42367458/)<br>Cureus | 2022 · 10 | P/A | Urgent/emergency adult principal HFrEF and any-position decompensation features. Exclude elective stays and selected conditions. | Survey logistic and linear regression; Elixhauser; coded concurrent conditions and disposition<br>Elixhauser, hospital covariates, death, LOS, charges, price adjustment, disposition, POA mentioned, missingness addressed | WSC | table, baseline, model table, figure, Stata |
| [Yang Y, 2026 (PMID 41527672)](https://pubmed.ncbi.nlm.nih.gov/41527672/)<br>Cureus | 2015–19 · 10 | — | Adult cystic fibrosis with/without liver disease. Exclude ages >100 and incomplete key fields. | Survey logistic and linear regression; confirm completeness of ICD-10 2015 quarters<br>hospital covariates, death, LOS, charges, cost, coded events, missingness addressed | WSC | table, baseline, model table, Stata |

### Obstetrics and pediatrics

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Zhong QY, 2018 (PMID 29720114)](https://pubmed.ncbi.nlm.nih.gov/29720114/)<br>BMC Pregnancy Childbirth | 2007–12 · 9 | A | Delivery by codes and DRGs, psychosis in any position. Address missing race. | Survey logistic using SAS and SUDAAN; coded obstetric/neonatal endpoints<br>hospital covariates, LOS, charges, coded events, DRG, missingness addressed | WSC | table, baseline, SAS, SUDAAN |
| [Ahmad N, 2019 (PMID 31886056)](https://pubmed.ncbi.nlm.nih.gov/31886056/)<br>Cureus | 2010–14 · 9 | P | Ages 12–40, principal CCS pregnancy/birth complications, co-coded drug dependence. | Weighted logistic; utilization and complication summaries<br>LOS, charges, coded events, CCS | W | table, baseline, model table, figure, time plot, SPSS |
| [Ling N, 2018 (PMID 29661199)](https://pubmed.ncbi.nlm.nih.gov/29661199/)<br>Pediatr Rheumatol Online J | 2000–11 · 9 | — | Ages 14–21 with pregnancy endpoint DX/PR groups from CCS; SLE 710.0. | Survey logistic, marginal risk differences, linear; coded maternal/fetal endpoints<br>hospital covariates, LOS, charges, coded events, CCS, missingness addressed | W, V | table, baseline, Stata |
| [Pankaj A, 2020 (PMID 33224654)](https://pubmed.ncbi.nlm.nih.gov/33224654/)<br>Cureus | 2010–14 · 9 | — | Emergency/non-elective pediatric stays, cannabis DX and prescription opioid overdose. | Logistic; demographic and psychiatric/substance covariates | — | table, model table, SPSS |
| [Rubens M, 2022 (PMID 35705610)](https://pubmed.ncbi.nlm.nih.gov/35705610/)<br>Sci Rep | 2010–14 · 9 | — | Delivery via DX, PR and DRG; survivors identified by prior cancer codes. | Explicit weights, strata, and cluster; survey contrasts; modified Elixhauser<br>Elixhauser, hospital covariates, death, LOS, coded events, CCS, DRG, missingness addressed | WSC, TW | table, baseline, model table, SAS |
| [Zahid S, 2022 (PMID 35708290)](https://pubmed.ncbi.nlm.nih.gov/35708290/)<br>J Am Heart Assoc | 2002–19 · 9+10 | A | Delivery DX/PR plus any-position PCOS; coded cardiovascular conditions. | Trend weights, survey regression and temporal comparisons; reports small-cell threshold<br>hospital covariates, LOS, cost, coded events, missingness addressed | WSC, TW, small cells | table, baseline, figure, flow, time plot, SPSS |
| [Nicholls-Dempsey L, 2023 (PMID 37876770)](https://pubmed.ncbi.nlm.nih.gov/37876770/)<br>Eur J Obstet Gynecol Reprod Biol X | 2004–14 · 9 | — | Delivery-defined admissions grouped by ZIP income. ICD diagnoses and delivery procedures. | Regression adjusted using selected baseline covariates; coded maternal/neonatal endpoints<br>coded events | — | table, SPSS |
| [Farmakis IT, 2026 (PMID 41914188)](https://pubmed.ncbi.nlm.nih.gov/41914188/)<br>Eur Heart J Acute Cardiovasc Care | 2016–20 · 10 | — | Pregnancy and puerperium with acute PE. ICD-10 codes for advanced reperfusion therapy. | Weighted descriptive counts by therapy; contrasts in-hospital outcomes<br>death | W | table, baseline, figure |
| [Rocha CN, 2026 (PMID 41803237)](https://pubmed.ncbi.nlm.nih.gov/41803237/)<br>Sci Rep | 2018–22 · 10 | — | Full-term low-risk hospital deliveries via coded eligibility; labor induction via procedure codes. | Annual weighted rates and group comparisons; cesarean and coded maternal outcomes<br>death, LOS, charges, coded events | W | table, figure, time plot, SPSS |

### Oncology

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Akinyemiju T, 2016 (PMID 27595733)](https://pubmed.ncbi.nlm.nih.gov/27595733/)<br>BMC Cancer | 2007–11 · 9 | P | Principal colorectal malignancy, resection, metastatic proxy via secondary codes. | Modified Deyo; logistic mortality/complications, linear LOS and multinomial stage<br>Charlson, death, LOS, coded events | — | table, baseline, model table, SAS |
| [Yun J, 2017 (PMID 28955300)](https://pubmed.ncbi.nlm.nih.gov/28955300/)<br>Front Neurol | 1998–2013 · 9 | P | Principal CNS lymphoma diagnoses and craniotomy/biopsy PR. Exclude alternative diagnostic approaches. | Charlson; logistic for coded complications; hospital teaching/size<br>Charlson, hospital covariates, LOS, coded events | — | table, model table, SAS |
| [Farber NJ, 2018 (PMID 29430511)](https://pubmed.ncbi.nlm.nih.gov/29430511/)<br>Bladder Cancer | 2001–12 · 9 | — | Ages 40+, bladder cancer plus radical cystectomy; urinary diversion defined by PR. | Cochran–Armitage and logistic; CCR-derived cost; coded complications<br>hospital covariates, death, LOS, cost, CCR, price adjustment, coded events | — | table, model table, figure, time plot, SAS |
| [Han H, 2021 (PMID 34235874)](https://pubmed.ncbi.nlm.nih.gov/34235874/)<br>Cancer Med | 2005–14 · 9 | P/S | Adult principal solid cancer plus secondary metastasis and secondary AF; CCS for major OR PR. | 29 Elixhauser conditions excluding cancer; log LOS/cost, logistic; doubly robust IPTW sensitivity<br>Elixhauser, hospital covariates, death, LOS, charges, cost, CCR, price adjustment, CCS, missingness addressed | W | table, baseline, figure, time plot, SAS |
| [Lee DU, 2022 (PMID 35938366)](https://pubmed.ncbi.nlm.nih.gov/35938366/)<br>J Gastric Cancer | 2011–17 · 9+10 | — | Gastric cancer plus gastrectomy codes; age strata and sequential multivariable adjustment. | Logistic for mortality and coded surgical complications; LOS and discharge comparisons<br>hospital covariates, death, LOS, charges, price adjustment, disposition, coded events, DRG | — | table, baseline, figure, flow, forest, R |
| [Chen Y, 2020 (PMID 33212422)](https://pubmed.ncbi.nlm.nih.gov/33212422/)<br>Breast | 2005–14 · 9 | S | Breast cancer and secondary metastasis, critical-care PR; excludes hospitals never recording palliative care. | Weights/strata/clusters; logistic and APC; CCS principal groups and Elixhauser excluding cancer<br>Elixhauser, hospital covariates, LOS, charges, cost, CCR, price adjustment, CCS | WSC | table, model table, figure, time plot, SAS |
| [Kim SJ, 2023 (PMID 36928807)](https://pubmed.ncbi.nlm.nih.gov/36928807/)<br>Sci Rep | 2010–14 · 9 | P/S | Principal breast cancer and secondary metastases plus palliative V66.7. | Survey logistic and linear for LOS and charges; inflation adjustment<br>hospital covariates, death, LOS, charges, price adjustment, DRG | W, V | table, baseline, model table, figure, flow, time plot, SAS |
| [Harris CA, 2024 (PMID 37578024)](https://pubmed.ncbi.nlm.nih.gov/37578024/)<br>Acta Obstet Gynecol Scand | 2017–20 · 10 | — | Hospital vaginal/cesarean delivery; cancer types via DX and mutually exclusive contraception via DX/PR. | Multinomial model for procedure categories<br>hospital covariates | W | table, figure, SPSS |
| [Lee KC, 2025 (PMID 40267974)](https://pubmed.ncbi.nlm.nih.gov/40267974/)<br>Ann Coloproctol | 2005–18 · 9+10 | — | Liver resection for colorectal metastasis, compare iron-deficiency anemia. Exclude incomplete outcomes. | Weighted stratified clustered logistic; prolonged LOS and unfavorable disposition<br>hospital covariates, death, LOS, disposition, coded events | WSC | table, baseline, figure, flow, SAS |

### Health services and disparities

| Study | Data years and era | Slot | Cohort, exclusions and comorbidity details | Methods and outcomes | Survey | Outputs and software |
| --- | --- | --- | --- | --- | --- | --- |
| [Vallabhajosyula S, 2019 (PMID 31315497)](https://pubmed.ncbi.nlm.nih.gov/31315497/)<br>J Am Heart Assoc | 2000–14 · 9 | ? | AMI and cardiogenic shock with palliative V66.7. Similar cohort to PAC study, different exposure. | Deyo, matched results and adjusted logistic labeled hierarchical; trend weights<br>Charlson, hospital covariates, death, LOS, disposition | W, V, TW | table, baseline, model table, figure, time plot, SPSS, R |
| [Palejwala SK, 2017 (PMID 28607826)](https://pubmed.ncbi.nlm.nih.gov/28607826/)<br>Surg Neurol Int | 2002–12 · 9 | P/S | Elective principal cervical myelopathy with secondary OPLL subgroup. Exclude revisions and ambiguous PR. | Compares surgery type by region and socioeconomic factors; exclusions enumerated | — | figure |
| [Neifert S, 2018 (PMID 30607106)](https://pubmed.ncbi.nlm.nih.gov/30607106/)<br>JSLS | 2013–14 · 9 | — | Sigmoidectomy by procedure and indication, grouped by neighborhood income. | APR-DRG and CCS-coded complications; matching, survey logistic/linear<br>hospital covariates, death, LOS, charges, coded events, CCS, DRG | WSC | table, baseline, figure, SAS |
| [Vallabhajosyula S, 2020 (PMID 33305205)](https://pubmed.ncbi.nlm.nih.gov/33305205/)<br>CJC Open | 2005–16 · 9+10 | P/S | Principal AMI, secondary shock and circulatory support PR. Compare sexes. | Deyo; trend weights, logistic and annual estimates, coded concomitant care<br>Charlson, hospital covariates, death, LOS, charges, cost, disposition | W, V, TW | table, baseline, figure, time plot, SPSS |
| [Singh S, 2021 (PMID 34295973)](https://pubmed.ncbi.nlm.nih.gov/34295973/)<br>Surg J (N Y) | 2016–17 · 10 | P | Principal bypass PR and obesity DX; uninsured/insured and ZIP income groups. | Survey logistic; Elixhauser and hospital covariates; coded events<br>Elixhauser, hospital covariates, death | W, V | table, SAS |
| [Cannon HR, 2023 (PMID 36356700)](https://pubmed.ncbi.nlm.nih.gov/36356700/)<br>Curr Probl Cardiol | 2020 · 10 | — | COVID-19 and coded myocarditis, stratify by race. Also describes STEMI comparison groups. | Elixhauser; logistic death, linear LOS and charges; coded organ support<br>Elixhauser, hospital covariates, death, LOS, charges, cost, coded events | — | table, figure, Stata |
| [Sarica C, 2023 (PMID 37876670)](https://pubmed.ncbi.nlm.nih.gov/37876670/)<br>Lancet Reg Health Am | 1993–2017 · 9+10 | A | Any-position DBS PR; exclude conditions that share lead-implantation codes. Multiple imputation. | Logistic for treatment and OLS for charges; annual plots, disclosure statement<br>hospital covariates, death, LOS, charges, price adjustment, DRG, missingness addressed | W, small cells | table, figure, time plot, SPSS, R |
| [Romo Valenzuela A, 2024 (PMID 38295038)](https://pubmed.ncbi.nlm.nih.gov/38295038/)<br>PLoS One | 2016–19 · 10 | — | Adult elective CABG/valve PR. Exclude LVAD, transplant, endocarditis and incomplete fields. | Van Walraven score; CCR and price index; LASSO-assisted selection and modeled income<br>Elixhauser, hospital covariates, death, LOS, charges, cost, CCR, price adjustment, disposition, coded events, missingness addressed | — | table, baseline, model table, figure, flow, time plot, Stata |
| [Nguyen A, 2025 (PMID 39316343)](https://pubmed.ncbi.nlm.nih.gov/39316343/)<br>J Racial Ethn Health Disparities | 2020 · 10 | P/S | Principal versus secondary U07.1; CCSR and refined Elixhauser groups. | Weighted age-standardized rates, cluster adjustment, spline-adjusted logistic, CCR costs<br>Elixhauser, hospital covariates, death, charges, cost, CCR, disposition, coded events, CCSR | W, V | table, baseline, model table, Stata |
