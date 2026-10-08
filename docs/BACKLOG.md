# Implementation backlog

This is the ordered, reviewable backlog for the agreed scope. Implementation began on 2026-10-08. Exact function names can change during API review. Each item should become a small issue/PR as implementation proceeds.

## Initial implementation progress

| ID | State on 2026-10-08 | Remaining acceptance work |
|---|---|---|
| NIS-001 | Saad authorized implementation and supplied public maintainer metadata. | Ali's full preferred public name and optional ORCID. |
| NIS-002 | Installable development package, generated help/namespace, NEWS, citation, and contribution guide. Local Windows source check passes. | Cross-platform evidence and final coauthor metadata before release. |
| NIS-003 | Deterministic invented fixtures with component joins, variable slot counts, missingness, and hand-calculated summaries. | Audited annual contracts and full inference/model/export expectations. |
| NIS-004 | CI configured for five platform/R combinations; local source tarball inspection passes. Four hosted checks passed at 7576a14. | Complete R devel and hosted checks for the final review fixes. |
| NIS-005 | Located six annual parquet datasets; metadata inventory tool added. | Conversion history, release revisions, missing/label provenance, prefiltering, and hardware details. |
| NIS-007 | Experimental DuckDB sessions, local parquet views, explicit projections, and exact BIGINT collection. Unsafe decimal/wide numeric identifier collection is refused; strings require positive digits. | Reviewed annual metadata and conversion profiles. |
| NIS-008 | Synthetic tests cover unique keys, unmatched rows, shared-field conflicts, and row-preserving component joins. Structural failures expose check/component/fields and aggregate counts. | Annual source component and alias review. |
| NIS-009 | Aggregate structural reports for identifiers, weights, code types, and missing required fields. | Full annual field-availability and missing-reason contracts. |
| NIS-011 | Experimental user-declared code sets and lazy flags with explicit scope, missingness, applicability, and provenance. | Annual metadata, canonical transformations, dictionaries, and clinical review. |
| NIS-012 | Invented SQL/R parity tests for exact/prefix matching and all missingness policies; common-slot sensitivity tests across invented year layouts. | Audited annual slot contracts and clinical cohort validation. |

Local aggregate checks accepted the 2018–2022 input structures and matched
the official Core row counts. The 2017 input was rejected for invalid YEAR
values. The tools ran read-only queries and performed no source writes. These checks do not authenticate
release revisions, merged components, derived fields, or statistical methods.
Receipts remain in ignored local validation storage.

No annual analysis capability has passed its validation gates. The installed
roadmap continues to report every year as a target.

The draft implementation is [PR #1](https://github.com/MSaadAsif/easyNIS/pull/1).
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
