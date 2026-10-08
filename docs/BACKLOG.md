# Implementation backlog

This is the ordered, reviewable backlog for the agreed scope. Implementation began on 2026-10-08. Exact function names can change during API review. Each item should become a small issue/PR as implementation proceeds.

## Initial implementation progress

| ID | State on 2026-10-08 | Remaining acceptance work |
|---|---|---|
| NIS-001 | Saad authorized implementation and supplied public maintainer metadata. | Ali's full preferred public name and optional ORCID. |
| NIS-002 | Installable development package, generated help/namespace, NEWS, citation, and contribution guide. Local Windows source check passes. | Cross-platform evidence and final coauthor metadata before release. |
| NIS-003 | Deterministic invented fixtures with component joins, variable slot counts, missingness, and hand-calculated summaries. | Audited annual contracts and full inference/model/export expectations. |
| NIS-004 | All five hosted checks pass at d5b5283, including R devel, offline tool tests, and source tarball inspection. | Verify subsequent implementation increments; R 4.1 remains a provisional minimum. |
| NIS-005 | Located six annual parquet datasets; metadata inventory tool added. | Conversion history, release revisions, missing/label provenance, prefiltering, and hardware details. |
| NIS-006 | Core specification audit reader now follows each source's column guide, validates internal structure, and preserves the previous registry on failure. Offline invented tool tests added to CI. | Saved source snapshots for all annual components, missing-value formats, and review by both authors. |
| NIS-007 | Experimental DuckDB sessions, local parquet views, explicit projections, and exact BIGINT collection. Unsafe decimal/wide numeric identifier collection is refused; strings require positive digits. | Reviewed annual metadata and conversion profiles. |
| NIS-008 | Synthetic tests cover unique keys, unmatched rows, shared-field conflicts, and row-preserving component joins. Structural failures expose check/component/fields and aggregate counts. | Annual source component and alias review. |
| NIS-009 | Aggregate structural reports for identifiers, weights, code types, and missing required fields. Lazy selections retain imported schema; field status distinguishes caller omission from unverified absence and reports requested SQL NULL counts. | Source-unavailable versus conversion-omitted fields and annual special missing-value meanings still require audited contracts. |
| NIS-011 | Experimental user-declared code sets and lazy flags with explicit scope, missingness, applicability, and provenance. | Annual metadata, canonical transformations, dictionaries, and clinical review. |
| NIS-012 | Invented SQL/R parity tests for exact/prefix matching and all missingness policies; common-slot sensitivity tests across invented year layouts. | Audited annual slot contracts and clinical cohort validation. |
| NIS-013 | Experimental full-population native survey construction and subsequent logical domains, with explicit hospital WR method and fail-on-singleton policy. | Annual field/conversion review, scientific approval of design choices and additional inference policies. |
| NIS-014 | Experimental pooled designs separate year-specific hospital/stratum keys and require combined-total, average-annual-total or pooled-proportion intent. Native weights scale only for explicit average annual totals. | Reviewed annual mappings/year composition, scientific approval and later historical/trend rules. |

Local aggregate checks accepted the 2018–2022 input structures and matched
the official Core row counts. The 2017 input was rejected for invalid YEAR
values. The tools ran read-only queries and performed no source writes. These checks do not authenticate
release revisions, merged components, derived fields, or statistical methods.
Receipts remain in ignored local validation storage.

No annual analysis capability has passed its validation gates. The installed
roadmap continues to report every year as a target.

The foundation implementation merged in [PR #1](https://github.com/MSaadAsif/easyNIS/pull/1).
Experimental matching is described in [COHORTS.md](COHORTS.md). The next import
increment should audit official layouts and conversion profiles, then define
canonical transformations without losing raw meanings. Machine-readable join
failures do not complete the annual missing-reason contract in NIS-009.

The latest Windows R 4.6.1 source check passes with Status OK and 473 assertions,
without failures, warnings, or skips. Offline examples and a 44-entry source
tarball inspection pass. Independent review findings about decimal precision,
normalization, whitespace, row order, extreme integer bounds, and structured
schema diagnostics were fixed and verified. These are experimental behavior
checks, not annual or clinical certification. Private checks still accept
2018–2022 structures and reject the 2017 input. Direct official-layout retrieval
remains blocked by timeouts; cached source snapshots and coauthor metadata
review are still required before annual adapters or approved inference.

The metadata continuation found that the 2017 and 2022 official Core column
guides differ, so the updater's fixed positions could not parse every target
year correctly. It now reads the guide, checks year/revision and field/record
structure, supports a strictly offline cache run, and stages the registry only
after every requested year succeeds. See [METADATA-AUDIT.md](METADATA-AUDIT.md)
for commands, evidence limits, and the next annual/conversion review steps.
No annual registry or support promotion was produced by this increment.
The tool suite passes 60 assertions with no failures, warnings, or skips.
The unchanged package passes 473 assertions and a fresh Windows R 4.6.1 source
check with Status OK, including offline examples. The 44-entry source tarball
excludes the audit tools, snapshots, private inputs, and validation receipts.
Generated documentation is current. The new tool suite runs separately in CI;
hosted evidence for this continuation must be checked after its commit is pushed.

## Explicit-start development environment

On 2026-10-08 Saad confirmed autonomous implementation after an explicit start,
including independent review, adequate verification, commits, pushes and
protected development merges. Experimental statistical code may merge while
scientific validation and release approval remain with Saad and Ali. Scheduling
requires a separate explicit request. See [AUTONOMY.md](AUTONOMY.md) for the loop
and [SKILL-ROUTES.md](SKILL-ROUTES.md) for the inspected skill choices.

The local verification harness checks the pinned R documentation generator,
package/tool assertions, source build/check, tarball boundaries, and an isolated
installed import/validation/cohort workflow across six invented year labels.
The offline merge-gate suite covers 36 positive and rejection scenarios, including
stale head/base reviews, missing or failed CI, missing local evidence, dirty
worktrees, read-only behavior and head-matched protected merge requests.
GitHub main protection now requires all five existing R/platform jobs, a current
base and resolved conversations, including for administrators.

The resumed column-selection increment preserves imported schemas and flag
definitions through lazy selections, and reports aggregate SQL NULL counts for
requested present fields. A public-call regression reproduced four cases where
omitted source names could be reused as flags. The fix reserves both imported
names and recorded flag definitions, including case variants. Selection history,
quoted columns, row/value preservation, repeated selection, absent fields,
sentinel preservation and closed sessions are covered by invented tests.

The initial Windows verification passes 510 package assertions, 60 tool
assertions, the 36-scenario merge-gate suite, offline examples and a source check
with Status OK. The 47-entry tarball excludes private inputs and local receipts.
The installed public workflow exercises selection, field status and source-name
collision rejection for every invented 2017–2022 label. Final committed-head
verification, hosted checks and independent review are required before merging.
No annual capability or scientific approval was promoted.

The selection increment merged in [PR #2](https://github.com/MSaadAsif/easyNIS/pull/2)
after clean-head verification, both independent reviews with zero blockers,
and all five hosted platform/R checks. Main's checks passed after the merge.

The next annual acceptance action is saving official source snapshots and
reviewing component/missing-value contracts and conversion history. A bounded
direct Core-specification retry on this workstation still timed out on
2026-10-08; no source-byte snapshot or provisional registry was produced.
Canonical annual transformations remain dependent on that evidence.

## Experimental survey-design continuation

The invented-input portion of NIS-013 now constructs a complete supplied-year
native `survey` design before selecting logical domains. Raw columns and exact
identifiers are retained, and provenance records source/component receipts,
selection/flag history, the unverified population declaration, method, survey
version and initial options. Domain accounting separates FALSE and unknown
indicators and retains original PSU information. No global survey options are
set by easyNIS, weights are not scaled and an FPC is not fabricated.

A public-call regression found that native BIGINT weight arithmetic produced
incorrect probabilities. Safely representable integer weights are now converted
to doubles for the native design while raw columns remain intact. Precision-
unsafe integer weights, nonfinite reciprocals, invalid structural fields,
conflicting hospital strata and singleton strata are refused. The focused suite
passes 69 assertions, including missing outcomes, nondefault caller options,
large string/BIGINT identifiers, unknown and empty domains, and valid zero
estimates and variances.

Direct `survey` reference comparisons and independent hospital-level WR
arithmetic cover domains absent from some hospitals. The initial full Windows
verification passes 576 package assertions, 60 metadata-tool assertions, offline
examples, a Status OK source check and installed domain workflows across all
six invented labels. Subsequent provenance/policy cases require the final
committed-head verification. Hosted checks and independent review are required
before merge. See [SURVEY.md](SURVEY.md) for the contract and exact reference
calculations. This eager prototype has no benchmarked memory envelope and
provides no approved annual inference, pooling, model or export capability.

The single-year increment merged in [PR #3](https://github.com/MSaadAsif/easyNIS/pull/3).
Final clean-head verification passed 579 package assertions and 60 tool assertions,
Status OK and all installed workflows. Refreshed independent reviews found zero
blockers; all five hosted jobs passed against the current main base. A separate
10-row reference with three and two hospitals per stratum independently matched
total 72/variance 1632 and mean 4.5/variance 0.9697265625. Scientific approval
remains pending.

## Experimental pooling continuation

NIS-014 now pools complete single-year designs with explicit common columns
and estimand intent. Year-specific exact hospital/stratum keys retain reused
annual identifiers as distinct design units. Raw annual objects and weights
remain recoverable. Native weights divide by included years only when the caller
requests average annual totals. Prior domains, repeated years and incompatible
fields/classes/factor levels are refused. Pooled proportions are weighted across
supplied discharges rather than an arithmetic average of annual proportions.

The focused suite passes 41 assertions. Direct year-keyed native references and
independent WR arithmetic cover different annual weights, zero-domain hospitals,
missing outcomes, exact BIGINT identifiers and combined/average/proportion
interpretations. Initial full verification passes 620 package assertions,
60 tool assertions, a Status OK source check and offline examples. The 54-entry
tarball passes private-boundary inspection. The installed six-year pool verifies
24 year-specific hospitals, 12 year-specific strata and independent combined
and average domain totals/variances after the source sessions close. Final clean
committed-head evidence, hosted checks and independent review remain required
before merging. See [POOLING.md](POOLING.md).

The next synthetic criterion is NIS-015's explicit numeric estimates, standard
errors, degrees-of-freedom/inference choices and outcome-missing accounting.
Annual metadata, conversion profiles and author scientific approval still gate
annual claims. Model, disclosure and rendering capabilities remain separate.

## Foundation and metadata

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-001 | Confirm written scope and public author metadata. | Plan review. | Shared-understanding confirmation, maintainer email, names, author roles; ORCIDs if provided. |
| NIS-002 | Create an installable standard R package. | 001 | DESCRIPTION, generated namespace/help, MIT metadata, NEWS, citation, contribution guide; source install/check succeeds. |
| NIS-003 | Generate invented fixtures covering 2017–2022 contracts. | 002 | Deterministic generator, no record-derived data, documented values/expected estimates, varying slots/components/missingness. |
| NIS-004 | Establish CI and tarball checks. | 002–003 | R checks on selected platforms/versions; examples run offline; no book/private input in source tarball. |
| NIS-005 | Inventory actual parquet conversions locally. | File paths from authorized user. | Year/revision, component counts, schema/types, conversion history, labels, missing-reason loss, RAM/disk metadata documented locally. |
| NIS-006 | Audit annual 2017–2022 metadata. | 005 | Registry facts cite official layouts/data elements; annual fields, identifiers, slot counts, missing rules and derived tools reviewed by both authors. |

## Import, harmonization, and cohorts

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-007 | Prototype DuckDB session and parquet import. | 003, 006 | Typed fields and identifiers preserved; quoted paths/names; explicit connection ownership; resources close after success/errors. |
| NIS-008 | Enforce component join contracts. | 007 | Duplicate/unmatched keys reported; intended join cardinality; no silent row multiplication or conflicting field overwrite. |
| NIS-009 | Implement structured validation reports. | 006–008 | Distinguish source-unavailable, conversion-omitted, record-missing, and user-omitted fields; clear unsupported-year/component messages. |
| NIS-010 | Define canonical variable/label transformations. | 006, 009 | Raw meanings recoverable; documented units/levels and annual applicability; conversion provenance retained. |
| NIS-011 | Implement reviewed ICD matching and code-set provenance. | 010 | Principal/secondary/all scopes, slot policy, coding system, valid periods, exact/prefix behavior and missing policy tested. |
| NIS-012 | Prove R/SQL cohort parity and cross-year slot behavior. | 011 | Numeric agreement on synthetic edge cases; common-slot sensitivity example; no leading-zero loss or regex surprises. |

## Survey and models

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-013 | Specify single-year survey design and domain behavior. | 010–012 | Reviewed fields/design rules; missing/invalid weights and singleton policy; full-population design before cohort selection. |
| NIS-014 | Implement pooled estimands and year-specific keys. | 013 | Annual/combined/average annual results distinguished; reused IDs do not merge across years; no unconditional weight scaling. |
| NIS-015 | Validate inference against explicit survey reference. | 013–014 | Estimates/SEs/df match references including zero-domain hospitals, sparse groups, reused IDs, and missing outcomes. |
| NIS-016 | Implement survey GLMs and sample-accounting reports. | 015 | Linear/logistic/Poisson-family fits; native fit returned; formula, missing policy, df, reference levels and warnings retained. |
| NIS-017 | Validate model effects and diagnostics. | 016 | Coefficients/SEs/CIs/tests agree; correct OR/risk/rate/mean interpretation; interactions, sparse levels, aliasing and convergence tested. |

## Tables, performance, and release

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-018 | Build numeric descriptive and regression tables. | 015, 017 | Weighted estimates separate from raw counts; missingness/units/reference groups/denominators explicit; native numeric values verified. |
| NIS-019 | Implement disclosure review and suppression. | 018 | Cases 0/1/9/10/11, high weighted-small raw cells, hospital counts, margins and complementary disclosure tested; no hidden raw fields in exports. |
| NIS-020 | Implement CSV/HTML/Word rendering adapters. | 018–019 | All formats preserve interpretation and suppression; optional dependencies fail with useful guidance; Word layout visually inspected. |
| NIS-021 | Add reproducible analysis report and full-workflow vignettes. | 007–020 | Synthetic quickstart executes; versions, domain/code sets, weights, df, missing policy and sanitized provenance included. |
| NIS-022 | Benchmark 40 GB workstation workflows. | 015–021, 005 | One full year and 2017–2022 pool measured with narrow projections; peak RAM/disk/timing recorded; numerical agreement and supported limits stated. |
| NIS-023 | Run private licensed validation per initial year. | 006–022 | Official count/summary checks and independent survey/model reference receipts for each 2017–2022 year; discrepancies resolved or documented. |
| NIS-024 | Test usability with an independent colleague. | 021–023 | Install-to-export workflow completed without coaching; confusing steps fixed and feedback recorded. |
| NIS-025 | Ship stable v1 and prepare CRAN submission. | 004, 020–024 | Release checklist passes; tag/changelog/docs agree with capability matrix; no unvalidated year or input claim. |

## Expansion and paper

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-026 | Add 2023 adapter. | 025 + validation access. | Missing race/geography, rurality and adjusted charges handled explicitly; current designs/tool versions verified. |
| NIS-027 | Add 2012–2016 and split 2015. | 025 + validation access. | ICD-9/ICD-10 parts preserved; reviewed cross-era cohorts; design/weight and absent-component behavior verified. |
| NIS-028 | Add 1993–2011 including trend weights. | 027 + validation access. | 1998/redesign/revision changes, zero trend weights and 2000 charge-specific rule verified; trend comparability documented. |
| NIS-029 | Add early-year single-year support. | 028 + validation access. | 1988–1992 layouts/designs tested; pooled/trend claims separately justified or explicitly unsupported. |
| NIS-030 | Add raw ASCII and selected converted-format importers. | Stable metadata/import contract. | Official layouts audited, missing reasons/labels retained, results agree with reference loaders; redistribution terms checked for bundled metadata. |
| NIS-031 | Establish paper comparison and adoption evidence. | Begin during implementation; mature release for results. | Compared tasks/safeguards/correctness/performance, real research use, community feedback, public iterative development. |
| NIS-032 | Prepare JOSS submission and archival release. | 025, 031 + current journal eligibility. | Honest archived coverage, reproducible public example, open-source terms, DOI, AI disclosure and human scientific review. |

## Added after the Biostatistics review

| ID | Work | Depends on | Acceptance criteria |
|---|---|---|---|
| NIS-033 | Define verified parquet input profiles. | 005–006; before 007 is finalized. | Source-preserving and legacy merged profiles distinguished; identifier/weight aliases verified against year/provenance; prefiltered input and lost missing/label information reported. |
| NIS-034 | Verify derived-variable and model-scale provenance. | 010–011, 016–018. | Versioned supplied comorbidity/classification fields; unsupported POA-dependent scoring refused; broad disposition labels preserved; charges/cost/base-year and transformed-outcome interpretations explicit. |

NIS-033 and the v1 metadata/model safeguards in NIS-034 are release requirements. New scoring algorithms, cost-conversion helpers, and additional model families remain later capabilities with separate validation gates.

NIS-026–030 are later release work, not requirements for the first 2017–2022 release. Paper claims must follow the coverage and behavior of the submitted version.
