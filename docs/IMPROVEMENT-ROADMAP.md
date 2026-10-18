# easyNIS improvement roadmap

Updated: 2026-10-18. This document records completed literature research and
prioritizes candidate improvements. It is a planning reference, not authorization
to implement every proposal. The completed HOCM myectomy-versus-alcohol septal
ablation study remains a reference, not new work.

## Current decisions

- The published-study challenge set (roadmap item 1) is complete. The research
  supports making easyNIS a verifiable NIS research-protocol layer around the
  existing `survey`/`srvyr` ecosystem. Priorities are re-phased around real-world
  use: first add cheap objective checks inside functions analysts already call,
  then use study friction to decide what to build. More paper-specific model
  wrappers are not the priority.
- The completed HOCM study is available as an
  [existing reference](https://msaadasif.github.io/NIS-Saad-HOCM-SRT-Pacing/).
  Do not recreate or schedule it as new work.
- HOCM backlog item 3 (curated cardiac device code sets) and item 8 (AHRQ
  Elixhauser computation) remain **deferred** until the user explicitly resumes
  them. Preserve only their requirements noted in the literature report; do not
  start either extension indirectly under another roadmap item.
- Roadmap item numbers differ from HOCM backlog item numbers. The R1–R8 labels
  below are the literature report's ranks, used to avoid another numbering
  collision. Roadmap items and HOCM backlog items are separate numbering
  systems.
- Future implementation follows `AGENTS.md`: work on a branch, use invented
  public fixtures and independent MIT code, run focused `testthat` tests and
  `devtools::check()`, then request independent review. Keep licensed inputs,
  private paths, local validation receipts, and record-derived output out of
  the repository.

## 1. Published-study challenge set

Status: **done**.

The completed review examined 12 full-length original NIS studies across trends,
comparative procedures, disparities, rare outcomes, resource use, procedure
timing, coding transitions, and coding validity. Requirements were classified
as A (directly supported), B (available through established R tools), C
(repetitive NIS-specific work that may justify an improvement), or D
(unsupported, unclear, out of scope, or methodologically inappropriate).
Accessible methods were distinguished from insufficiently reported or
inaccessible details; conference-only material was excluded. The full report
is archived at `docs/research/2026-10-nis-literature-report.md`.

Headline: easyNIS should connect its existing NIS-specific primitives into a
verifiable research protocol, rather than add more model wrappers. Existing
tests establish agreement for core estimators on an invented 2017–2019 fixture;
the remaining design work is to broaden coverage and document annualization.
Other high-consequence gaps are objective preflight and schema checks,
cohort/code provenance, design-aware sensitivity reporting, disclosure
auditing, and cost validation. Synthetic end-to-end teaching workflows can
exercise that protocol without becoming new clinical research.

#### Report corrections

- The report says no design validation artifact exists. That is incorrect:
  `tests/testthat/test-design.R:28-117`, using
  `tests/testthat/helper-design.R:1-41`, compares `nis_design()` against a
  full-data survey design with a domain subset. It covers 2017–2019, core
  estimators and models, and two lonely-PSU settings at tolerance `1e-8`.
- `nis_comorbidity()` passes `poa = 1L` for every code because public NIS has
  no POA flags (`R/comorbidity.R:15-19,123-126`). Its stated difference is that
  it does not reproduce Stata-derived `ynel*` and `elixsum`
  (`R/comorbidity.R:35-42`).
- The study template has model-specific complete-case and unusable-model-matrix
  status handling, not a general preflight
  (`R/nis-new-study.R:106-155,175-223`;
  `inst/templates/nis-study/analysis.qmd:366-423`).

## Prioritized backlog from literature research

The phases order work around real-world use. Prefer checks that run
automatically inside functions analysts already call, catch objective errors,
and are cheap to build. Opt-in audit functions and new abstractions get built
only when a real study needs them. The literature report shows where published
NIS work goes wrong; real easyNIS use decides what is built next.

Status: **in progress on separate feature branches**.

### Phase A — automatic checks in existing functions (in progress)

#### A1. (part of R1) Extend `nis_design()` validation and make annualization explicit

Maps to roadmap item 3, independent statistical validation.

- **Why:** The report missed the existing agreement test in
  `tests/testthat/test-design.R:28-117`. It compares placeholder and full-data
  domain designs on invented 2017–2019 data for means, totals, `svyby`, logistic
  and Gaussian `svyglm`, median `svyquantile`, degrees of freedom, and a
  gtsummary table, under two lonely-PSU settings at tolerance `1e-8`. Remaining
  gaps are coverage breadth and documentation, not absence of validation.
- **First bounded deliverable:** Add a partial-year annualization warning
  inside `nis_design()`. Extend agreement cases to pooled years including
  partial 2015 Q4, `svyratio` and confidence intervals, invalid design rows,
  and annualized totals; document a short validation protocol covering cases,
  statistics, tolerances, and full-data reference construction.
- **Done when:** Extended cases agree within tolerance or limitations are
  documented, partial-year annualization cannot pass silently, and the protocol
  is documented. The user decides whether the placeholder strategy's
  **experimental** label can be removed.

#### A2. (part of R6) HCUP hospital rule in `nis_suppress()`

- **Why:** HCUP disclosure guidance requires at least two contributing
  hospitals. This objective check can run in the suppression function analysts
  already use.
- **First bounded deliverable:** Add the at-least-two-contributing-hospitals
  rule to `nis_suppress()` when the required data are available.
- **Done when:** Results identify cells supported by fewer than two hospitals.
  This is not a general secondary-suppression solver.

#### A3. (R7) Record cost provenance automatically in `nis_cost()`

- **Why:** Resource-use studies depend on distinguishing charges from costs and
  on reproducible CCR and inflation assumptions. The report identifies cost
  methodology and 2023 layout assumptions as unverified.
- **First bounded deliverable:** Have `nis_cost()` record the charge field, CCR
  field, inflation index and base year, missing-CCR count, and output type:
  nominal charge, adjusted charge, or estimated cost.
- **Done when:** Every result reports its charge, CCR, and inflation inputs;
  missing CCRs and output type are visible. 2023 remains marked unverified
  until its assumptions are checked against official documentation and data.

#### A4. PRDAY completeness by year and procedure slot

- **Why:** `nis_flag_pr_timing()` pairs procedure slots with matching PRDAY
  fields and distinguishes missing or sentinel timing, but timing availability
  can vary by year.
- **First bounded deliverable:** Add a small helper reusing
  `nis_flag_pr_timing()` semantics to summarize matched procedure-slot counts
  and known, missing, and sentinel day values by year.
- **Done when:** Output identifies absent PRDAY fields and reports denominators
  and completeness by year and slot. It does not impute a day or decide whether
  missingness is acceptable.

### Phase B — use-driven validation

Use easyNIS on the next real study. Log every point where workaround code was
needed, recording the friction only and never record-derived data, in line
with `AGENTS.md`. This replaces observing other researchers as the first source
of evidence.

### Phase C — build only when a real study needs it

#### R2. Objective checks in `nis_open()` and `nis_design()`; defer separate preflight

Maps to roadmap item 2, NIS study preflight and methodological audit.

- **Why:** The report finds recurring objective errors around years, survey
  fields, ICD regime, partial periods, and cost semantics. These checks are
  more likely to reach analysts as warnings in functions they already call.
- **First bounded deliverable:** Add objective warnings inside `nis_open()` or
  `nis_design()` for years, design fields, ICD regime, and charge-field
  comparability where definitions differ (for example, `TOTCHG_2023` versus
  earlier `TOTCHG`).
- **Done when:** Each warning names the observed fact and rule. A separate,
  declaration-based `nis_preflight()` remains deferred: analysts most likely
  to make these errors are least likely to run an optional audit.

#### R3. Small automatic cohort and code provenance

Maps to roadmap item 6, inspectable, reusable cohort definitions.

- **Why:** Code source, validity interval, diagnosis or procedure position,
  missingness policy, and ordered exclusions affect whether published cohorts
  can be reconstructed. Existing `nis_flag_*()` functions and `nis_attrition()`
  already execute useful cohort steps.
- **First bounded deliverable:** Have existing `nis_flag_*()` functions and
  `nis_attrition()` record what they did automatically, with a printer for the
  resulting provenance.
- **Done when:** The workflow exposes its executed flags and attrition
  transparently. A full cohort-definition object or DSL is considered only if
  needed; analysts often bypass parallel DSLs in favor of dplyr. Provenance
  does not curate clinical code sets.

#### R5. Start sensitivity analysis as a vignette pattern

Maps to roadmap item 4, reviewer-request challenge.

- **Why:** Alternate diagnosis positions, transfer and timing rules,
  overlapping-procedure handling, and transition-period choices can change
  results. `nis_dx_sensitivity()` reports descriptive points but not
  design-based uncertainty.
- **First bounded deliverable:** Show `purrr::map()` over named cohort variants
  with `nis_design()` to compare denominators, estimates, intervals, and
  exclusions.
- **Done when:** A synthetic vignette makes variant definitions and denominator
  changes visible. Add a function only if repeated real-study need appears; do
  not add regression methods or choose an estimand.

#### R4. Limit the annual manifest to fields easyNIS uses

Maps to roadmap item 7, source-backed annual compatibility audit.

- **Why:** The package accepts 2012 onward, but accepted years do not imply that
  every layout is verified. Fields used by easyNIS can change across releases.
- **First bounded deliverable:** Create a source-backed manifest only for
  fields easyNIS itself uses, marking each claim **verified**,
  **supported-with-assumptions**, or **unknown**.
- **Done when:** Each included field has a status and source note, and checks
  do not silently treat unknown fields as verified. Account for ongoing
  maintenance cost with each HCUP release; no broad pre-2012 expansion is
  implied.

#### Generic code-contradiction and mutually exclusive state audit

The coding-validity study makes internal code consistency part of the research
question; other studies expose incompatible recorded states. Specify
analyst-supplied Boolean rules only when a real study needs them. If built,
report deterministic per-rule counts and overlapping failures with traceable
definitions. No cardiac-device or other curated clinical code sets are added.

### Phase D — adoption (depends on audience)

#### R8. Synthetic teaching workflows using `nis_new_study()`

Maps to roadmap item 8, complete teaching studies.

- **Why:** Synthetic examples can teach the full protocol without using patient
  data or recreating the completed HOCM study. Their priority depends on
  whether easyNIS seeks users beyond the author and collaborators; teaching
  workflows and a published validation protocol matter mainly for that broader
  audience.
- **First bounded deliverable:** If broader adoption is intended, build small
  invented-data workflows for national trends, disparities/domain analysis,
  and procedure timing, with expected outputs and checks.
- **Done when:** Each workflow starts from `nis_new_study()`, documents cohort
  and design choices, produces cohort flow, a descriptive table, an outcome
  summary, a figure, and methods text, and passes expected-output checks.
  The completed HOCM study remains a separate reference.

#### Roadmap item 5. Observe other researchers using easyNIS (optional)

Only if the user authorizes it later, give researchers invented data and
observe unprompted completion, mistakes, workarounds, documentation searches,
and accidental unweighted analyses. Use findings to improve cohort rules,
errors, or documentation.

## Explicitly not recommended

- Broad pre-2012 support, including `TRENDWT` implementation, as a near-term
  expansion. Historical studies reveal demand, but the 2012+ design and annual
  layouts need validation first.
- Dedicated Joinpoint, propensity-score, marginal-effects, or multiple-
  imputation wrappers merely because papers used those methods. Use established
  R tools for general statistical methods.
- Longitudinal or readmission helpers that imply person linkage or post-discharge
  follow-up unavailable in NIS.
- State estimates from NIS; use a data source designed for state estimates.
- Post-2011 hospital volume inferred from sampled NIS discharge counts.
- Mechanized peer review or preflight that chooses confounders, causal claims,
  missing-data methods, or scientific validity on an analyst's behalf.

## Deferred requirements note

The literature report records requirements only for the two deferred HOCM
backlog items. The deferral remains in force; these notes do not authorize
implementation or scheduling.

- **HOCM backlog item 3 — curated cardiac device code sets:** retain only the
  requirement notes for source citation, code system and exact code/prefix
  semantics, validity dates, position/slot policy, overlap rules, and checks
  for conflicting categories. Provenance and generic contradiction audits may
  handle analyst-supplied definitions; they must not curate clinical code sets.
- **HOCM backlog item 8 — AHRQ Elixhauser computation:** retain only the
  requirement to record the exact comorbidity algorithm, software/version, code
  system, POA behavior where relevant, and whether the analysis used an index or
  individual indicators. Existing `nis_comorbidity()` must not be described as
  an AHRQ reproduction unless independently established. A new AHRQ-specific
  implementation remains deferred.

These are HOCM backlog numbers, not improvement-roadmap numbers. Roadmap item 3
is independent `nis_design()` validation; roadmap item 8 is synthetic teaching
workflows.

## Open questions and source-access limits

- **Intended audience:** Who is the intended user base beyond the author?
- **Design equivalence:** Existing tests show agreement for core estimators on
  invented 2017–2019 data. How broadly does the placeholder strategy agree with
  a full-data survey design for partial 2015 Q4, ratios and confidence
  intervals, domain-singleton strata, invalid design rows, and annualized
  totals?
- **Annual layouts:** Which fields and assumptions are verified for each
  supported year, especially the 2023 layout and CCSR inputs? Loader acceptance
  is not layout verification.
- **ICD-9 intent:** Is experimental ICD-9 support intended only for the 2012–Q3
  2015 transition era, or is broader historical support a separately justified
  goal? Full pre-2012 support would also require addressing `TRENDWT` and the
  earlier sampling design.
- **PRDAY completeness:** How complete are procedure-day fields by year and
  slot, and how much does completeness vary among procedures used in a study?
- **Cost validation:** Which CCR source/year and inflation convention should be
  recorded, how should missing CCRs be summarized, and what evidence is needed
  before the 2023 charge field is treated as verified?
- **Study-method access:** Detailed methods or supplements were inaccessible or
  not retrieved for Thomas and Canner (PMC access), Mpody (publisher access),
  Wright (Supplement 1), de Havenon (supplemental PDFs), Patel (primary methods),
  and Adalbert (detailed method body). The general-surgery timing study's DOI
  metadata were not recovered reliably. These are extraction gaps, not evidence
  that the studies omitted those methods.

The full literature review contains the study inventory, capability matrix,
source notes, and detailed rationale for these priorities. It is archived
at `docs/research/2026-10-nis-literature-report.md`.

## Next steps

Phase A is underway on separate feature branches. Next, use easyNIS on the
next real study and log workaround friction for Phase B. Let that experience
decide which Phase C work is needed, and resolve the intended audience before
prioritizing Phase D. Preserve the explicit deferrals for HOCM backlog items 3
and 8. Follow `AGENTS.md`: work on a branch, use invented public fixtures and
independent MIT code, run focused `testthat` tests and `devtools::check()`, and
request independent review before merge. Keep licensed inputs, private paths,
local validation receipts, and record-derived outputs out of the repository.

## Related references

- [Analyst workflow](ANALYST-WORKFLOW.md)
- [HOCM SRT pacing gaps backlog](backlog/hocm-srt-pacing-gaps.md)
- [Deep research prompt](DEEP-RESEARCH-PROMPT.md)
- [HCUP NIS checklist](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp)
- [Official NIS documentation](https://hcup-us.ahrq.gov/db/nation/nis/nisdbdocumentation.jsp)
- [2017 JAMA assessment](https://jamanetwork.com/journals/jama/fullarticle/2664461)
- [2026 JAMA Network Open assessment](https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2844384)
