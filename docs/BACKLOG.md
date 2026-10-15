# Implementation backlog

This is the ordered, reviewable backlog for the agreed scope. Implementation began on 2026-10-08. Exact function names can change during API review. Each item should become a small issue/PR as implementation proceeds.

## Initial implementation progress

### Workshop readiness priority, 2026-10-14

**Hold on regression export (NIS-020).** Regression-table disclosure review
merged in [PR #45](https://github.com/MSaadAsif/easyNIS/pull/45) at `c77ac7c` on a
VERIFIED receipt, while a concurrent independent review of the same head
(`a8c7e3f`) found one blocking leak: response binary/two-level status is decided
from the whole response, so a group whose own values are 0/1 within a
multi-valued response gets only a nonzero check and a shown coefficient can
reveal a 3-row count that the descriptive review of the same field suppresses.
The missing-outcome count is also unchecked. A follow-up PR on
`claude/easynis-regression-disclosure-groups` applies the descriptive row rule
to every checked group. Do not merge regression-table export until that
follow-up merges; its exporter must recompute the corrected review. The
follow-up is implemented and locally verified on that branch (draft PR #46);
it still needs independent review and hosted checks. Two writers also shared
the main checkout; parallel writers need separate worktrees.

Grouped joint disclosure review merged in
[PR #44](https://github.com/MSaadAsif/easyNIS/pull/44); all five resulting main
jobs passed at `2d12519c5f1288d4ebd39ef930ad45a24bcbc9dd`. NIS-035's bounded
grouped review/export criterion is complete.

Regression-table disclosure review (NIS-019) merged in
[PR #45](https://github.com/MSaadAsif/easyNIS/pull/45) at `c77ac7c`. See
[REGRESSION-DISCLOSURE.md](REGRESSION-DISCLOSURE.md). Three review rounds had
added interaction and joint cells, all-zero and all-one constant columns, the
zero/one recoding of two-valued responses and nonzero checks for multi-valued
responses. A fourth review of `a8c7e3f` found that binary and two-level status
was still decided from the whole response, so a 0/1 or 1/2 group inside a
multi-valued response was published while the descriptive review of the same
field restricted to that group suppressed it, and that the excluded missing
count was unchecked. The follow-up on
`claude/easynis-regression-disclosure-groups` replaces the response splits with
one helper applying the descriptive row rule to each checked group's own
values, adds the model missing check (a failure suppresses every row and
`unweighted_n`, as the descriptive row is suppressed) and adds a consistency
test against descriptive reviews of seven probe groups. Numeric predictors
with three or more values stay uncrossed, a group's multi-valued response is
checked only for nonzero rows (as a descriptive mean is), and the retained
model frame is trusted; all are documented limitations. Focused invented cases
pass 300 assertions with hand-counted references; descriptive code is
unchanged. Precommit verification passes 2,820 package assertions, 216 tool
assertions, source Status OK and installed workflows. The intercept,
lower-order, joint-crossing and group rules suppress more than the first draft
and need Saad and Ali's policy review. Regression-table export remains held
until the follow-up merges. No scientific or annual support is promoted.

Numeric factor grouping merged in
[PR #43](https://github.com/MSaadAsif/easyNIS/pull/43); all five resulting main
jobs passed at `4fdd813b0bb16e725b735d8d68f7d87bced57684`. Groups use full-design
domains, declared factor order and explicit missing-membership policy, while
outcome exclusions remain per field. No scientific or annual support is promoted.

The next bounded NIS-035 criterion reviews one grouped constructor result
jointly and exports its presentation through the existing CSV/HTML/Word path.
Exact field and complete domain-history identities must drive every suppression
and margin target, preserving repeated statistics within each group. Acceptance
covers unequal true group partitions that formerly collapse into a false
declaration-only target, cross-group protected pairs and hospital unions, nested
subtotals, group-dependent binary scales, missingness, current domains, pooled
hospital reuse, malformed provenance and complete ordinary-review compatibility.
Installed six-year factor -> grouped table -> one joint review -> CSV/HTML
checks include primary/complementary suppression, the unchanged whitelist,
formula defense and repeatable output. Overall rows, between-group tests and
combining separately constructed tables remain outside this increment. Full
verification, independent review and protected hosted checks remain required.

The old field-only algebra reproduces a false declaration-only rejection of
valid separate group partitions when its refusal is removed in an isolated
reference. The domain-aware implementation passes 24 independent probes,
including manually specified hidden-unit/pair equations checked with SVD,
hospital unions and complete ordinary-result/export compatibility. Preliminary
specification and standards reviews have no unresolved findings. Full precommit
verification passes 2,520 package assertions, 216 tool assertions, source Status
OK and installed public workflows. Final clean-head verification, pinned
independent review and protected hosted checks remain required.

The quality-marker workflow merged in
[PR #42](https://github.com/MSaadAsif/easyNIS/pull/42); all five resulting main
jobs passed. No scientific or annual support is promoted.

The next bounded NIS-021 workshop composition uses explicit character-quality
handling in the existing six-year installed workflow. Replace two invented
noncohort codes per annual fixture with lowercase quality markers; preserve
all raw fields and full annual populations. Pool before explicitly excluding
the 12 unknown cohort predicates. The same 360 domain rows, 288/354 outcome
samples, independent scalar/GLM/WR references and reviewed descriptive outputs
must remain unchanged. Check exact raw/flag alignment, retained policy, unknown
accounting, repeatable outputs and cleanup. This illustrates a declared policy,
not clinical, conversion, annual or licensed-data readiness. Full verification,
independent review and protected hosted checks remain merge requirements.

The updated invented workflow passes direct execution and full precommit
verification: 2,391 package assertions, 216 tool assertions, source Status OK
and installed workflows. These are the existing package-suite counts; new
composition checks run in the example and installed smoke. The reference mask
explicitly excludes unknown predicates before GLM fitting and assigns their
original hospitals zero scores. Final clean-head verification, independent
review and hosted checks remain required.

The next bounded NIS-009/011/033 increment adds explicit opt-in handling for
documented HCUP character quality markers in selected diagnosis/procedure slots.
Default strict rejection remains unchanged. Lowercase `invl`/`incn` stay raw and
distinct; opted-in flags are unknown unless another selected slot positively
matches, regardless of the blank policy. Other malformed/case aliases still fail.
See [CHARACTER-MISSING.md](CHARACTER-MISSING.md) for primary sources, scope and
acceptance. No source correction, scientific approval or annual promotion is
implied. Full verification, independent review and protected CI precede merge.

Focused invented cases pass 89 assertions. Independent review also exercised
24 exhaustive scope/policy/normalization grids and 18 old/current default
comparisons. Review exposed a connection-collation bypass for uppercase aliases;
a public regression fails before the fix and passes with byte-exact marker
comparison. The initial full run passed 2,387 package and 216 tool assertions,
source Status OK and installed workflows. Corrected full verification passes
2,391 package and 216 tool assertions, source Status OK and installed workflows.
The character-policy increment merged in
[PR #41](https://github.com/MSaadAsif/easyNIS/pull/41) after successful clean-head
verification, final independent review and all five PR/main hosted jobs.

The next bounded NIS-013/022 increment removes full-discharge data-frame
deduplication from hospital/stratum validation. Acceptance: retain the first
exact mapping per hospital, compare every row and preserve conflict/singleton
rejections, raw rows/types/order, native design and population/inference output.
Verify shuffled/repeated hospitals, first/middle/late conflicts and existing
exact/BIGINT/domain/pooled references. Profile the actual eager path, compare
identical configured workloads with repeated measurements and count failures;
keep licensed measurements private and do not claim a six-year memory envelope.
Full verification, independent review and protected CI precede merge.

Hospital-map focused tests pass 96 assertions; initial full precommit verification
passes 2,302 package assertions, 216 tool assertions, source Status OK and installed
workflows. Independent old/new probes preserve native design, population and
provenance with zero correctness blockers. Five alternating fresh-process runs
on the same invented seven-million-row input complete without failures; native
preparation medians are 27.04 seconds before and 22.03 seconds after, with
non-overlapping ranges. Separate profiles identify mapping deduplication before
and native survey construction as the remaining limiter. A public developer
harness reproduces the invented workload/accounting checks; its prepare/run path
was executed successfully. Updated full verification also passes the same gates,
and independent review accepts the bounded measurement. The increment merged in
[PR #40](https://github.com/MSaadAsif/easyNIS/pull/40) after final pinned independent
review and all five PR/main hosted jobs. No memory envelope or annual support
is promoted; see [SURVEY.md](SURVEY.md) for the bounded measurement and context.

The next bounded NIS-021/033 onboarding increment reuses `nis_import()` and
`nis_validate()` in an installed invented input-check walkthrough and
[input guide](INPUT-CHECKS.md). Acceptance: distinguish rejected mixed YEAR
(no validation report), accepted input missing canonical design fields, and
structurally clean input with unverified annual/conversion metadata. Preserve
FALSE readiness, explicit caller declarations and component/field-state meanings;
do not map aliases, repair years or export diagnostics. Installed smoke must
assert exact statuses, repeatability, privacy and cleanup on success and injected
failure. Full verification, independent review and protected CI precede merge.
Corrected precommit verification passes 2,275 package assertions, 216 tool
assertions, source Status OK and installed workflows. The cleanup smoke retains
the native connection handle to confirm it is invalid after the owned session
clears its handle. Independent execution reproduces statuses and success/error
cleanup with zero review blockers. Clean committed-head evidence, final pinned
review and hosted checks remain required before merge.

The input-check walkthrough merged in
[PR #39](https://github.com/MSaadAsif/easyNIS/pull/39) after successful clean-head
verification, both final independent reviews and all five PR/main hosted jobs.
The six-year workshop composition likewise merged in
[PR #38](https://github.com/MSaadAsif/easyNIS/pull/38). These complete bounded
invented onboarding/workflow increments, not licensed analyst readiness.

Saad prioritized a simpler practical workflow for analysts beginning topics on
Saturday 2026-10-17 with 2017–2022 converted Parquet files. The first usability
increment addresses repeated outcome-model formulas: declare exact outcome
families and shared predictors once, retain each native fit and outcome-specific
sample, and reject a failing batch without partial results. See
[MODEL-BATCHES.md](MODEL-BATCHES.md) for its bounded NIS-016/021 acceptance cases.
It must pass independent numerical references, installed public calls, full
verification, independent review and protected CI before merging.

The first implementation passes 141 focused assertions and independent
hospital-score WR references for all three model links on full/domain/pooled
invented designs. Full precommit verification passes 2,107 package assertions,
216 tool assertions, all 36 merge-gate cases, source Status OK, tarball
inspection and installed workflows. Both preliminary reviews found zero
blockers. Clean committed-head evidence, final independent review and hosted
checks remain required before merge. No annual support is promoted.

The model-batch increment merged in
[PR #35](https://github.com/MSaadAsif/easyNIS/pull/35) after clean-head verification,
both final independent reviews and all five hosted checks. The next bounded
NIS-013/021 usability increment allows compound `nis_domain()` predicates over
retained fields after constructing the full design. It must preserve exact native
subsetting/PSU information, raw columns, full-population accounting, existing
string-field histories and explicit FALSE/unknown counts. Formula environments,
globals and arbitrary functions must not affect results. See [SURVEY.md](SURVEY.md)
for the grammar, source-type/missingness limits and acceptance cases. Focused
predicate/survey tests pass 133 assertions without failures, warnings or skips.
Full verification, independent review and hosted checks remain required.
Precommit verification passes 2,171 package assertions, 216 tool assertions,
all 36 merge-gate cases, source Status OK, tarball inspection and installed
workflows. The installed drive compares predicate and logical-column domains
with exact native design/population/provenance parity for all six invented
year labels before checking independent inference. Final clean-head evidence,
independent review and hosted checks are required before merge.

The compound-domain increment merged in
[PR #36](https://github.com/MSaadAsif/easyNIS/pull/36) after clean-head verification,
both final independent reviews and all five hosted checks. The next bounded
NIS-010/016/021 usability increment creates caller-declared analysis factors in
distinct new columns, preserving raw source fields, rows and native survey
structure. Explicit one-to-one level/label declarations must reject undeclared
observed values, keep NA/NaN missing and retain declaration provenance. This
is not a canonical annual mapping or an inferred missing-code contract. See
[ANALYSIS-FACTORS.md](ANALYSIS-FACTORS.md) for typing, contrast and acceptance
limits. Full verification, independent review and hosted checks are required.
Focused factor tests pass 104 assertions. Full precommit verification passes
2,275 package assertions, 216 tool assertions, all 36 merge-gate cases, source
Status OK, tarball inspection and installed workflows. Independent probes
confirm typed category/missingness behavior and model coefficients/covariance
on single-year/domain/pooled invented designs. Both preliminary reviews found
zero blockers; final clean-head evidence, pinned review and hosted checks remain
required before merge. No annual or scientific approval is changed.

The analysis-factor increment merged in
[PR #37](https://github.com/MSaadAsif/easyNIS/pull/37) after clean-head verification,
both final independent reviews and all five hosted checks. The next NIS-021
increment composes factors, compound adult/code-flag domains and a shared
LOS/event outcome batch in the installed six-year example. Existing reviewed
descriptive outputs/scalar references must remain unchanged. Independent GLM
and hospital-score WR matrix references must verify both links and their separate
288/354-case samples. The example must restore nondefault caller options and
export only fixed declarations and existing reviewed descriptive values.
[WORKFLOW.md](WORKFLOW.md) documents the template and unresolved migration gates.
Full verification, independent review and hosted checks remain required.
Precommit verification passes 2,275 package assertions, 216 tool assertions,
source Status OK and installed workflows. Independent closed-form group/delta
references also reproduce both models. Reviewed CSV/HTML bytes match the prior
example, and injected early/late failures restore options, close connections and
remove temporary inputs/incomplete outputs. Both preliminary reviews found zero
blockers. Final clean-head verification, pinned reviews and hosted checks remain
required before merge.

This priority does not promote annual capabilities or replace scientific choices.
Legacy identifier/weight aliases, input completeness, global singleton adjustment,
derived-variable meaning and disclosure/export differences require explicit
review. Practical readiness needs an executable install-to-analysis-to-export
workflow and licensed input evidence; a shorter model call alone does not meet
that goal. Next increments should address analyst-facing setup and remaining
end-to-end blockers with the existing validation gates.

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
| NIS-015 | Experimental scalar total/mean/proportion API with explicit outcome missingness, unadjusted WR variance, interval df and confidence. Independent synthetic references added. | Full increment verification, independent review, licensed references and author scientific approval. |

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
committed-head evidence, hosted checks and independent review completed before
the pooling increment merged in [PR #4](https://github.com/MSaadAsif/easyNIS/pull/4).
Main's checks passed after merging. See [POOLING.md](POOLING.md).

NIS-015 now has explicit numeric estimates, standard errors, caller-selected
interval degrees of freedom/confidence and outcome-missing accounting in the
experimental `nis_estimate()` implementation. It retains the native result,
raw analysis design and complete constructor/domain provenance. It refuses
incompatible current options without mutation, and respects pooled total intent.
Independent hospital-level WR arithmetic covers full and sparse domains,
zero-contribution hospitals, unequal PSU counts, a stratum without observed
outcomes, reused annual IDs, negative sentinels and safe BIGINT outcomes.
The focused estimate suite passes 208 assertions with no failures, warnings or
skips, and generated help is current. Initial full verification passes 828
package assertions, 60 tool assertions, 36 merge-gate scenarios and a Status OK
source check. The 57-entry source tarball passes private-boundary inspection.
Installed public calls check annual and six-year totals, SEs, explicit t/normal
intervals and weighted proportions after source sessions close. Final clean-head
verification, independent review and hosted evidence remain required before merge.
See [ESTIMATES.md](ESTIMATES.md).
Annual metadata, conversion profiles and author scientific approval still gate
annual claims. Model, disclosure and rendering capabilities remain separate.

## Experimental model continuation

PR #5 merged after the cancelled macOS runner job was retried unchanged and
all five hosted checks passed. Its committed verification and independent
reviews remained bound to the same head/base. No gate was bypassed.

The first NIS-016 increment adds explicit Gaussian identity, quasibinomial logit
and quasipoisson log fits on native full-design domains. Complete-case exclusion
retains original hospitals. Formula fields, overlapping missing counts, analysis
weights, separate native/caller df, factor coding, warnings, aliases and complete
provenance are reported. Numeric coefficient inference remains on the link
scale. See [MODELS.md](MODELS.md) for the contract and independent sandwich
calculation. Transformations/offsets, interpreted effects and broader sparse/
convergence diagnostics remain separate NIS-016/017/034 acceptance work.
Windows verification after logical predictor coding correction passes 998 package assertions, 60 metadata-tool
assertions, 36 merge-gate scenarios, a Status OK source check, source-tarball
privacy inspection and installed three-family intercept references for every
invented year. Native contrast re-evaluation and reserved weight/offset names
were checked through public calls and corrected before this verification.
Final clean committed-head evidence, independent review and all five hosted
checks remain required before merging. No annual capability is promoted.
Logical FALSE/TRUE contrast matrices are retained without changing raw columns.
The warning continuation reproduces a native custom-contrast warning escaping
frame preparation while the same warning is captured during fitting. Preparation,
fitting and summary now share one handler that retains distinct messages in
diagnostics. Native coefficients/covariance, fitted contrast matrices and raw
caller columns remain intact. Verification and current-head review are required
before this continuation merges.

The model increment merged in [PR #6](https://github.com/MSaadAsif/easyNIS/pull/6)
after final clean verification with 998 package/60 tool assertions, a Status OK
source check, all five hosted jobs and refreshed independent reviews with zero
blockers. Separate reviewer calculations matched full/domain/pooled coefficients
and score-sandwich covariances for all three families, including logical coding.
The warning follow-up's corrected Windows verification passes 1,015 package
assertions, 60 tool assertions, all 36 gate scenarios, Status OK and installed
workflows. Final clean-head evidence, hosted checks and independent review remain
required. The next model acceptance work is transformed-outcome and exposure
offset contracts, followed by explicit effect interpretations and broader
diagnostics. Annual support and scientific approval remain pending.
Frame and custom contrast preparation both use the same warning handler. The
custom-contrast regression reproduces the former lost diagnostic message and
checks native numeric/coding parity and restoration of caller state.

## Experimental formula and exposure continuation

The warning increment merged in [PR #7](https://github.com/MSaadAsif/easyNIS/pull/7)
after clean-head 1,015 package/60 tool assertions, Status OK, all five hosted
jobs and refreshed independent reviews with zero blockers. Installed reviewer
probes covered custom contrast warnings, multiple distinct messages and warn=2.

The NIS-016/034 formula increment supports row-wise numeric Gaussian response
and predictor expressions and one positive log-exposure quasipoisson offset.
It records exact response/exposure expressions, source fields and modeled
scale; native coefficients stay on that scale. Invalid observed transformations
and exposures are refused instead of becoming silent missing exclusions.
Complete-case domains retain original hospitals, raw fields and pooled keys.
See [MODEL-FORMULAS.md](MODEL-FORMULAS.md) for the contract and acceptance cases.
Supplied terms metadata is discarded so it cannot replace checked expressions.
Native offset predictions are explicitly unsupported and marked in diagnostics
because the installed native predictor omits exposure; independent fitted-value
references include the offset. Corrected Windows verification passes 1,080 package assertions, 60 tool
assertions, all 36 merge-gate scenarios, source Status OK, tarball inspection
and installed transformed-mean/exposure-offset references for every invented
year. Clean committed evidence, independent review and hosted checks remain
required. Interpreted effects, broader diagnostics, annual
validation and scientific approval remain pending.

## Sparse model precision continuation

The formula increment merged in [PR #8](https://github.com/MSaadAsif/easyNIS/pull/8)
after clean-head 1,080 package/60 tool assertions, Status OK, all five hosted jobs
and refreshed independent reviews. Review caught supplied terms metadata
overriding the checked response and an upstream offset-prediction omission;
fresh formula construction and an explicit unsupported-prediction contract
resolved both findings. Resulting main checks passed.

The NIS-017 sparse-fixture continuation reproduces covariance errors up to
`1.54e-5` against final-mean independent hospital score sandwiches, exceeding
the existing `1e-7` absolute reference bound. Four outcomes and four sparse-factor
rows among 64 observations exercise full and hospital-absent domains for both
quasi families. Converged nonboundary quasi fits restart once from fitted
coefficients at unchanged epsilon `1e-10` and maximum 50 iterations. Lowering
epsilon was rejected because it also lowers R's QR threshold and can lose exact
aliases. Initial/final iterations, restart status and policy are retained.
Gaussian, boundary and nonconverged initial fits skip refinement. The native
final fit remains intact; initial and final warnings are retained. Focused
tests pass the unchanged covariance/interval bounds and quasi-family exact
aliases with whole-hospital missingness. Windows verification passes 1,171
package assertions, 60 tool assertions, all 36 gate scenarios, source Status OK,
tarball inspection and installed all-link/transformed/offset workflows for every
invented target year. Clean-head review and hosted checks remain required.
This is a numerical improvement with bounded
synthetic evidence, not a general sparse/separation guarantee or scientific
approval. Interpreted effects and annual validation remain pending.

## Explicit model contrast continuation

The sparse precision increment merged in [PR #9](https://github.com/MSaadAsif/easyNIS/pull/9)
after clean-head verification, independent review and all five hosted jobs.
The resulting main checks passed at `7bbaad2`.

The next NIS-017 increment adds caller-declared named coefficient contrasts.
Their variance uses the complete fitted coefficient covariance, including
interaction cross-terms. Caller-selected model df and confidence remain the
inference policies. Explicit interpretations distinguish link differences,
named-outcome Gaussian mean differences, logistic odds ratios, Poisson mean
ratios without exposure offsets, and Poisson rate ratios with exposure offsets.
Transformed Gaussian outcomes retain their modeled scale. Intercepts and
nonzero aliased terms cannot enter a difference contrast. Interpreted effects
require converged nonboundary fits; link differences retain diagnostic warnings.
The caller defines the compared covariate profiles. A coefficient vector alone
does not authenticate that comparison or establish a causal interpretation.

Focused verification passes 521 model assertions, including 178 new contrast
assertions. Initial full Windows verification passes 1,349 package assertions,
60 metadata-tool assertions, all 36 merge-gate scenarios, a source check with
Status OK, source-tarball inspection and installed independent slope/sandwich
contrasts for all six invented year labels. Direct native comparisons and
independent hospital score calculations cover interactions, domains, whole-
hospital missingness and pooled reused identifiers. Finite/infinite df, reverse
contrasts, reciprocal ratios, aliases, zero variance, transformed outcomes,
exposure semantics and numerical rejection paths are exercised. Clean committed-
head verification, independent reviews and hosted checks remain required.
No annual capability or scientific approval is promoted. The next acceptance
work is broader sparse/separation diagnostics, followed by numeric table
contracts; annual metadata and licensed validation retain their dependencies.
On 2026-10-09 a bounded direct retry of the official 2017 Core specification
again timed out after 30 seconds. No source snapshot or provisional registry
was produced; annual source and conversion review remain dependencies.

## Factor-support diagnostic continuation

The contrast increment merged in [PR #10](https://github.com/MSaadAsif/easyNIS/pull/10)
after clean-head verification, both independent reviews with zero blockers and
all five hosted jobs. Main's checks passed at `04a80c6`. Independent 144-row,
three-stratum, twelve-hospital
probes matched projected hospital-influence estimates and SEs within `7.8e-14`
and checked odds versus risk and exposure rates versus unequal-exposure means.

The next NIS-017 increment reports per-level supplied and analyzed row counts,
analysis weights and contributing hospitals for fitted factor/logical
predictors. Declared but unobserved levels retain zero support where their
source definition is recoverable. These counts describe the supplied domain
and complete-case analysis, without introducing a sparsity threshold or
claiming to detect separation. Pooling keeps year-specific hospitals distinct
and retains the analysis-weight divisor. Focused verification passes 370 model
and 178 contrast assertions with no failures, errors, warnings or skips. Full
Windows verification passes 1,376 package assertions, 60 metadata-tool
assertions, all 36 merge-gate scenarios, source Status OK, tarball inspection
and installed fixed reference counts for six invented years and a pooled
average-annual design. Cases cover whole-hospital missingness, domains, unused
declared levels, logical missingness and expressions, model-frame label
collisions, native covariance parity and caller-state preservation. Numeric-only
fits return an empty list without allocating an extra analysis-weight vector.
Clean committed-head verification, independent reviews and hosted checks
remain required before merge.
Review reproduced a formula ambiguity where `I(group)` and a distinct quoted
raw field named `I(group)` received the same native model-frame label. The old
public call returned duplicated support metadata instead of rejecting the
ambiguity. A failing public regression is retained locally. Distinct formula
terms now require unique model-frame labels, checked before named metadata and
contrast preparation. Valid quoted fields and separate expression/decoy cases
remain accepted. Corrected focused checks pass 373 model and 178 contrast
assertions with no failures, errors, warnings or skips; full corrected-source
verification is in progress. Independent probes also check three-level factor
coding, zero-analysis levels, whole-hospital exclusions and pooled year keys.
Independent review also reproduced rejection of previously accepted factors
with a declared NA level. Integer category-code matching and unnamed count
vectors now distinguish declared NA, literal `"NA"`, unused levels and true
missing codes without creating invalid data-frame row names. Raw named-factor
supplied counts follow raw codes; expression counts follow native evaluated
frames, which can recode a missing code into an NA level. Existing raw-field
missingness and complete-case exclusion remain unchanged. Corrected-source
verification passes 1,400 package assertions, 60 metadata-tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and the
installed annual/pooled workflows. The focused suites pass 394 model and 178
contrast assertions. Final clean committed-head evidence and refreshed
current-head reviews remain required before hosted checks and protected merge.
The existing covariance, fitting and factor coding contracts remain in force.
No annual capability or scientific approval is promoted.

The factor-support increment merged in [PR #11](https://github.com/MSaadAsif/easyNIS/pull/11).
Final clean verification passed 1,400 package assertions, 60 metadata-tool
assertions, all 36 merge-gate scenarios, source Status OK and installed annual
and pooled workflows. Independent specification and standards reviews found
no remaining blockers, including installed probes for duplicate model-frame
labels and explicit NA factor levels. All five hosted checks passed for the
reviewed head and the resulting main commit.

The first NIS-018 increment implements numeric descriptive tables under
[DESCRIPTIVE-TABLES.md](DESCRIPTIVE-TABLES.md). Explicit row declarations select
mean, proportion or total statistics and provide labels and units. Each row
retains its original scalar result, native design and provenance. Weighted
values remain separate from raw discharge counts; missingness, denominators,
year-specific hospital counts and pointwise inference policies remain explicit.
No rounding, suppression or rendering occurs. Disclosure status is unreviewed
and annual capability and scientific approval remain unchanged. Focused checks
pass 55 expectations; full source verification passes 1,455 package assertions,
60 metadata-tool assertions, all 36 merge-gate scenarios, source Status OK,
tarball inspection and the installed workflow for all six invented year labels.
Cases include independent hospital-level WR arithmetic, repeated and quoted
fields, per-field missingness, domains, pooled intent, zero results, invalid
specifications and caller-state preservation. Clean committed-head verification,
independent reviews and hosted checks remain required before protected merge.
Next table acceptance work is numeric regression tables, followed by a reviewed
disclosure policy and rendering adapters; grouping and comparison definitions
remain explicit future choices.
The numeric descriptive table merged in [PR #12](https://github.com/MSaadAsif/easyNIS/pull/12).
Clean committed-head verification passed 1,455 package assertions, 60 tool
assertions, all 36 merge-gate scenarios, source Status OK and the installed
workflow. Independent specification and standards reviews found zero blockers.
An independent installed probe checked unequal weights, field-specific and
whole-hospital exclusions, sequential domains, average annual pooling, exact
numeric/native preservation and duplicate declaration rejection. All five
hosted checks passed on the reviewed head and resulting main commit.

The next NIS-018 increment adds numeric regression tables under
[REGRESSION-TABLES.md](REGRESSION-TABLES.md). Explicit row declarations select
existing coefficients on the link scale. Exact coefficient inference, aliases,
undefined tests, factor coding, model sample accounting, diagnostics and full
provenance remain available without refitting, exponentiation or rounding.
A public regression reproduced duplicate coefficient names when a factor level
and a distinct numeric predictor share a label and one coefficient is aliased.
Model fitting now rejects duplicate fitted coefficient names before mapping
inference, including aliases; distinct nearby labels remain valid.
Focused verification passes 55 table and 180 model/contrast assertions, with
no failures, warnings or skips. Full source verification passes 1,512 package
assertions, 60 metadata-tool assertions, all 36 merge-gate scenarios, source
Status OK, tarball inspection and installed public workflows for six invented
year labels and a pooled design with 24 year-specific hospitals. Clean
committed-head verification, independent reviews and hosted checks remain
required before protected merge. Disclosure status remains unreviewed and no
annual support or scientific approval is promoted.
Next acceptance work is a documented disclosure/suppression contract and its
NIS-019 cases, followed by rendering adapters. Explicit interpreted-contrast
rows and grouped comparisons retain separate scope and scale decisions.
The regression-table increment merged in [PR #13](https://github.com/MSaadAsif/easyNIS/pull/13);
its head and resulting main checks passed.

The first NIS-019 increment reviews numeric descriptive tables under
[DISCLOSURE.md](DISCLOSURE.md). The caller states the suppressed count range,
zero policy, minimum contributing hospitals and additive margins; nothing is
defaulted. Checks use unweighted included, missing, nonzero, binary complement
and two-level counts and their native first-level hospitals. Declared margins
must hold exactly in raw counts. Complementary suppression covers rows on the
same field, single-margin recovery and disclosive or single-hospital suppressed
sums, fields determined by combined margins, and disclosive differences between
published unweighted counts. Only the presentation frame is an export
candidate; it omits raw missing, supplied, hospital and weighted denominator
fields and carries no extra attributes.

Independent review of the first head reproduced two exact recoveries: a
proportion row left published beside its complementary-suppressed count row,
and three margins that jointly determined a suppressed category. Both now have
failing-before regressions, together with tests for single-hospital sums,
nested missing counts, 1/2 coding, zero-valued hospitals, and logical and
BIGINT outcomes. Removing any of the four new repairs fails the focused suite,
which passes 93 expectations. Cases also cover counts 0/1/9/10/11 under both
zero policies, a 15,000 weighted total from three discharges, pooled reused
hospital IDs and declaration failures. Full verification, refreshed review and
hosted checks are required for the corrected head. Precommit corrected
verification passes 1,605 package assertions, 60 tool assertions, all 36 merge-
gate scenarios, source Status OK and installed reviews for six invented years.
Regression-table review, undeclared relations and rendering remain open.
The policy is not scientifically or legally approved.

The first disclosure increment merged in [PR #14](https://github.com/MSaadAsif/easyNIS/pull/14)
after clean-head verification, independent review and all five hosted checks.
The resulting main checks passed. Its review identified a documented combined-
subtotal recovery path, which the following bounded correction addresses.

The bounded NIS-019 correction closes recovery of selected disclosive sums
through combined declared margins. It freezes each relation's original
primary-hidden parts and distinct primary-field pairs, then checks those sums
against all declared equations. Repairs consider connected margin components.
If declarations alone determine a protected hidden target, the complete review
fails without a presentation. The procedure remains experimental and does not
enumerate all subsets or solve nonnegative/whole-number constraints. Additive
raw counts retain multiplicity; raw equality does not establish disjoint groups.

Public disjoint indicators reproduce A = 3, B = 4, C = 30, D = 30 and S = C+D.
Publishing all, S and E formerly recovered the seven-discharge A+B group. The
corrected review also suppresses S. The installed smoke now sources
`inst/examples/disclosure-subtotals.R` through the installed package and checks
that recovery and exact preservation of shown numeric values. The focused
disclosure suite passes 114 expectations without failures, warnings or skips;
the old implementation fails seven assertions in the initial reproduction.
Cases include three primary-hidden parts, pairs without a shared relation,
hospital-only and zero sums, declaration-only hidden zeros, and a two-level
group of 12 discharges confined to one hospital. Generated help is current.
Precommit Windows verification passes 1,626 package assertions, 60 metadata-tool
assertions, all 36 merge-gate scenarios, source Status OK, a 75-entry tarball
inspection and installed public workflows including the subtotal reproduction.
Final clean committed-head verification, independent review and hosted checks
remain required before merge. No annual support or scientific/publication
approval changes. The next acceptance work is disclosure-preserving rendering;
regression-table review and larger unchecked cross-relation sums remain separate.
The bounded correction merged in [PR #15](https://github.com/MSaadAsif/easyNIS/pull/15);
its head and resulting main checks passed.

The first NIS-020 increment adds `nis_export_table()` under
[EXPORT.md](EXPORT.md). It writes only a rechecked disclosure review's
presentation, to CSV or HTML with base R. Descriptive and regression tables are
refused. Each review is recomputed from its retained results and recorded
policy and must match exactly, so edits to the presentation, audit, provenance
or table estimate columns are refused even when consistent across them. The
retained results, including design data that supply suppression counts, are
not authenticated. CSV
writes whole numbers in full and other values with 17 significant digits, which
any correctly rounding parser reads back exactly, with empty suppressed cells
and no audit fields. HTML escapes caller text, records the
experimental scope, count basis and policy, rounds only to caller-chosen
significant digits, and contains no suppressed value. Output is staged and
renamed; existing files are replaced only on request. Independent review of
the first head reproduced an exported hidden value after a consistent
multi-field relabel, a forged policy note and forged counts; each now has a
failing-before regression. The focused suite passes 122 expectations covering infinite df, non-ASCII, comma, quote and newline
labels, markup in labels and units, rounding, argument errors, extension
mismatch, missing directories and replacement. The installed smoke exports the
subtotal reproduction in both formats. Word output, regression-table export and
spreadsheet formula neutralization remain open; annual support and scientific
approval are unchanged.

Independent current-head export review reproduced missing confidence levels
when every row was suppressed and a level just below one displayed as 100
percent. HTML now retains an exact separate confidence column on every row;
interval suppression still hides all bounds. A failing-before public regression
covers three confidence levels with exact and rounded displays. The focused
export suite passes 150 expectations. Standalone notes explicitly identify
unchecked larger combinations of declared margins. Final verification and
refreshed independent review are required for this correction.
The macOS CI run rejected the decimal near-one fixture after it parsed as one;
the boundary fixture now uses machine epsilon to preserve a value below one
without changing production validation or weakening the confidence case.
The first export increment merged in [PR #16](https://github.com/MSaadAsif/easyNIS/pull/16);
the resulting main checks passed at `50c5d14`.

The next NIS-020 increment closes the documented spreadsheet-formula gap in
CSV export. A new required `formula_text` argument handles text cells that
begin with `=`, `+`, `-`, `@`, their full-width forms, a tab, a carriage
return or a line feed: `"refuse"` names
each affected column and row id and writes nothing, `"prefix"` writes a
leading `'`, and `"keep"` writes the text unchanged. HTML requires `NULL`.
Every text column is checked, including caller ids and units; numeric columns
are unaffected. The new public regression fails on the previous code, which
wrote such labels unchanged. Implementation surfaced two defects before commit:
a raw carriage-return byte in the pattern was lost when R parsed the source,
and columns without affected cells added empty entries to the refusal message.
Both are covered; the test asserts the exact refusal message. Independent
review of the first head found that line feed and the full-width forms listed
by OWASP were missing and that the empty-entry repair was untested. Both
were fixed, and mutants removing each character class or the repair now fail
the focused suite. `utils::read.csv()` splits a quoted carriage return, so that
case is checked in the written bytes. The installed smoke refuses and then
prefixes an invented `=HYPERLINK(...)` label and `@` id. Word output and
regression-table export remain open; annual support and scientific approval
are unchanged.
The formula-text increment merged in [PR #17](https://github.com/MSaadAsif/easyNIS/pull/17);
the resulting main checks passed at `b164ee1`.

The next NIS-020 increment adds Word output with `format = "docx"`. It uses
the optional officer package, now in Suggests and the verification doctor;
without it the call names `install.packages("officer")` and writes nothing.
HTML and Word share one display builder, so the Word table has the HTML
header, cells, suppression text and notes. Labels and units with characters
that XML cannot hold are refused with the column and row id; officer
otherwise failed with a parser error. Tests compare every Word cell and note
with the HTML export for exact and rounded tables, require every text node in
every XML part to be a caption, header, cell or note string and cover refusal,
argument and missing-package paths. Visual inspection through Word's PDF
conversion found that officer's default equal column widths broke words
mid-word. The first head moved to landscape Letter, an 8-point table style
and widths proportional to each column's longest word.

Independent review of that head (`135cd5a`) found two blocking problems.
A 45-row table still split rows across pages, separating interval bounds from
their rows, and the documentation understated mid-word breaks: exact tables
broke headers, `Suppressed` and status text, and a long identifier label did
the same in a three-digit table. Every row is now marked unsplittable and the
test counts the marks. Cell margins are narrowed. When the longest words
cannot fit, header and package text keep their width and caller text and
estimates wrap; any word counts at most 24 characters. Word renderings of the
three-digit table show no breaks; the exact table keeps all header and package
text whole while units, labels and 17-digit estimates wrap; the 45-row table
keeps every row on one page with repeated headers. The review also led to an
officer 0.5.0 minimum, xml2 in Suggests, U+FFFF coverage and a stronger
hidden-value test. Invalid UTF-8 labels still give R's encoding errors rather
than guidance, as in HTML.

The refreshed review of `cb918e8` confirmed both repairs in Word renderings,
including 45-row exact and three-digit tables with no row spanning pages, and
found one blocking documentation error: a caller word longer than the
24-character cap can still break when the table otherwise fits. EXPORT.md now
says so and describes the proportional scaling used when even header and
package text exceed the page. Tests now check row-property and cell-margin
placement with XPath and that header and package columns keep their estimated
widths, which previously surviving layout mutants would fail. The testthat
floor is 3.1.7 for mocked bindings, the example checks the officer version,
and test sources use escapes for noncharacters. Corrected precommit
verification passes 1,912 package assertions, 60 metadata-tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and the
installed workflow. Clean committed-head verification, refreshed independent
review and hosted checks are required for the corrected head.
Regression-table disclosure review and export remain open; annual support and
scientific approval are unchanged.

The Word increment merged in [PR #18](https://github.com/MSaadAsif/easyNIS/pull/18)
after clean committed-head verification, independent specification and standards
reviews with zero blockers, and all five hosted checks. The protected merge
gate passed for the reviewed head and base. Scientific approval and annual
support remain unchanged.

The next bounded export follow-up closes automated layout coverage gaps noted
in review. Public Word exports now exercise caller words at 24, 25 and 120
characters without text truncation or width growth beyond the cap, header
width protection, proportional scaling of every column when protected text
exceeds ten inches, and lone carriage returns in both labels and units without
mutating the review. The scaling case uses exact binary df/confidence values
solely to exercise long scientific strings, not to recommend inference choices.
EXPORT.md removes an example that overstated when that branch is reached.
The export suite passes 301 assertions. Independent in-memory mutants removing
the cap, header protection and proportional scaling fail the new public-document
cases. Precommit verification passes 1,927 package assertions, 60 metadata-tool
assertions, all 36 merge-gate scenarios, a source check with Status OK, tarball
inspection and the installed workflow. Clean committed-head verification,
current-head independent review and hosted checks remain
required before this follow-up merges. Next larger acceptance work is
regression-table disclosure review and a reproducible synthetic workflow report;
annual metadata and licensed validation retain their external dependencies.

## Offline synthetic workflow continuation

PR #19 merged with all five head and resulting main jobs passing at `2572f5e`.
The first NIS-021 increment adds an installed offline import-to-reviewed-export
example and a fixed Markdown report under [WORKFLOW.md](WORKFLOW.md). Its
explicit report whitelist includes versions, code/domain declarations, design
fields, weights/estimand, df/confidence, outcome missingness and disclosure
policy. Retained results, design data, local source paths and suppressed values
are omitted. CSV and HTML contain only the reviewed presentation. The README
now documents the executable quickstart and implemented tables/contrasts/exports.

Independent hospital WR arithmetic checks the LOS mean 34/7, its SE and t
interval after domain selection and row-specific outcome exclusion. A rare
indicator demonstrates primary suppression. Installed verification runs the
example twice and checks exact repeatability, sanitized metadata and reviewed
exports. Precommit verification passes 1,927 package assertions, 60 metadata-tool
assertions, all 36 merge-gate scenarios, source Status OK, a 79-entry tarball
inspection and installed public workflows including both quickstart runs.
Clean committed-head evidence, independent review and hosted checks remain
required before merge. Formal vignettes and integrated
pool/model examples remain NIS-021 acceptance work. Regression-table disclosure,
annual evidence and scientific approval retain their separate gates.

## Decimal formatting follow-up

PR #22 merged with all five reviewed-head and resulting main jobs passing at
`f99fb5c`. A public export regression then reproduced rounded HTML and Word
using comma decimal marks under `OutDec = ","`, while exact values and CSV
used points. Rounded whole numbers could retain a trailing comma. The shared
display builder now requests a decimal point explicitly without changing
caller options. Public tests compare CSV/HTML bytes and Word text under both
options for exact and three-digit output, preserve the review and check the
caller option. The installed smoke repeats the rounded HTML comparison.
Precommit verification passes 1,942 package assertions, 65 tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and installed
workflows. Both independent reviews found zero blockers. Clean committed-head
verification and hosted checks are required before merge. Annual support and
scientific approval are unchanged.

The decimal increment merged in [PR #23](https://github.com/MSaadAsif/easyNIS/pull/23)
after clean-head verification, independent specification and standards reviews
with zero blockers and all five hosted jobs. Resulting main checks also passed.

## Exact two-level disclosure follow-up

An independent public-call audit found that two distinct doubles, 1 and
`1 + .Machine$double.eps`, were merged by numeric-to-text grouping. A level of
three discharges across three hospitals and a level of twelve in one hospital
both remained shown and exported. The review now groups by exact value
positions, retaining its existing count and hospital policy. The public
regression failed before the fix and passes after it, covering both failures,
a safe eleven-discharge level, reversed row order, missing-outcome exclusion,
unchanged input and suppressed CSV cells. Installed verification exercises
the same count/hospital/safe cases through invented parquet inputs.
Precommit verification passes 1,951 package assertions, 65 tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and installed
workflows. Independent specification review found zero blockers, including
additional negative-value cases and compatibility with constant/three-level
outcomes. Clean committed-head verification, final independent reviews and
hosted checks are required before merge. This fixes experimental behavior and
does not promote annual support or scientific approval.

## Inventory filename year-hint correction

A public developer-tool regression reproduced year hints taken from a parent
directory, a prefixed filename and a filename with an extra suffix. Uppercase
filenames were inventoried but lost their hints. NIS-005 inventories now use
only complete `NIS_YYYY.parquet` filenames, case-insensitively, in both file and
schema receipts. An invented conflicting `YEAR` value confirms that hints are
filename declarations rather than inspected discharge years. Receipt notes and
the contributor guide state this boundary.

The new cases fail twice on the old implementation and pass after the fix.
Precommit verification passes 1,966 package assertions, 90 tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and installed
workflows. Clean committed-head verification, independent review and all five
hosted checks are required before merge. The next annual action remains saving
official source snapshots and reviewing the bounded parquet-only input profile;
unavailable upstream conversion history must remain unknown. Regression-table
disclosure/export still needs its own justified contract. No annual capability
or scientific approval is promoted.

## Inventory physical-schema correction

A developer-tool regression reproduced automatic Hive partition discovery in
folders such as `YEAR=2017/invented_partition=west`. The inventory fabricated
a column from the directory name and changed a stored INTEGER `YEAR` to
BIGINT. The schema query now disables partition discovery, matching the
experimental importer and reporting only file columns and their stored types.
Filename year hints and footer provenance retain their separate meanings.

The invented sourceable-tool and real CLI case fails three assertions before
the fix and passes afterward, checking exact column names/types, counts and
filename hints. Existing ordinary-directory cases still pass. Precommit
verification passes 1,966 package assertions, 97 tool assertions, all 36
merge-gate scenarios, source Status OK, tarball inspection and installed public
workflows. Clean committed-head verification, independent review and all five
hosted checks are required before merge. The correction does not change annual
support or scientific approval. Original official source-byte acquisition and
reviewed annual contracts remain the next metadata dependencies.

## Official source retrieval continuation

The next bounded NIS-006 action tests a remote network path for authentic
Core specification bytes, following failed workstation and browser routes.
The development-only fetcher requests the six fixed public Core URLs, tries
the alternate official host after failure, limits request duration and HTTPS
redirects, and records original response bodies/headers with URLs, HTTP results,
UTC times, lengths and SHA-256 hashes. Existing output directories are refused.
The separate GitHub job transfers these files as a short-lived artifact and
runs offline byte-preservation, error, fallback and no-overwrite cases.

Acceptance requires inspection of the actual remote manifest, verification
of transferred hashes and parser checks before any body enters the ignored
cache. A successful workflow or HTTP 200 is not a source-content validation.
All-failure receipts remain useful evidence and must not populate the registry.
The fetcher changes no annual support, licensed conversion history or scientific
approval. Original bytes, source review and component/missing-value contracts
remain the annual dependencies. See [METADATA-AUDIT.md](METADATA-AUDIT.md).
Precommit Windows verification passes 1,966 package assertions, 104 R tool
assertions, all 36 merge-gate scenarios, source Status OK, tarball inspection
and installed public workflows. The separate Python suite passes six offline
cases; an independent probe confirms all twelve failed requests retain exact
binary partial bodies, headers, hashes and complete failure receipts. Both
preliminary independent reviews found zero blockers. Clean committed-head
verification, final independent review and hosted checks remain required
before this increment merges; the remote acquisition result is still pending.

The retrieval increment merged in [PR #30](https://github.com/MSaadAsif/easyNIS/pull/30)
after clean verification, current independent specification/standards reviews
with zero blockers and all six hosted jobs. The remote runner retrieved all
six original public Core bodies from the canonical official host. Every
transferred body/header length and SHA-256 matches its remote receipt.

### Core specification filename and dataset identity

Original-byte parsing exposed a synthetic-fixture assumption: the 2019/2020
specification filenames contain `_V2`, but their dataset headers and field-row
filenames do not. The initial updater rejected these sources. A failing-before
invented updater regression reproduces the complete download/cache/registry
path. The correction separates `specification_revision` (requested filename)
from `dataset_name` (validated header/row identity). The ambiguous development
column `documented_revision` is removed; runtime APIs do not consume this CSV.
Wrong datasets/years and all previous structural checks remain enforced.
The official index's suffixed V2 dataset names differ from the specification
bodies; the registry records the latter and does not resolve licensed-release
identity from that discrepancy.

All six transferred bodies now pass parsing. Only after parser and transfer
checks were complete were unchanged bodies copied into the ignored cache.
The cached-only updater writes the first six-year provisional Core registry,
including source URLs, MD5 values and parse times. It establishes no licensed
conversion revision, special missing-value meaning or annual analysis support.
The saved sources document 40 diagnosis and 25 procedure slots in all six
Core specifications; fixture dimensions remain invented test choices.
The next annual acceptance steps are component specifications, load-format/
data-element missing-value contracts, conversion comparison and author review.
Precommit Windows verification passes 1,966 package assertions, 114 R tool
assertions (including 70 layout assertions), all 36 merge-gate scenarios, source
Status OK, a 90-entry tarball inspection and installed public workflows.
Independent checks reproduce both old-parser failures, match every public
registry fact to original bytes, and preserve the prior CSV after later-year
cache corruption. Both preliminary reviews found zero blockers. Clean-head
verification, final independent review and hosted checks are required before
the parser/registry increment merges.

The Core parser/registry increment merged in
[PR #31](https://github.com/MSaadAsif/easyNIS/pull/31) after clean-head
verification, independent specification/standards reviews with zero blockers
and all five hosted platform/R jobs.

### Component layouts and SAS reference acquisition

The next bounded NIS-006 action extends original-byte acquisition to an explicit
`all` profile: the official specification index, 23 initial-year component
layouts and their 23 SAS load reference programs. Core, Hospital and Severity
are requested for every 2017–2022 year; Diagnosis and Procedure Groups is
requested only for 2018–2022, following the official index. No component absence
is inferred from a failed request. The default CLI `core` profile remains six
Core specifications. Each receipt identifies year, component, kind and intended
filename; opaque response bodies, headers and transfer hashes are retained.

Relevant pull requests and manual dispatch can run the broader job, with at
most 94 bounded requests and a 35-minute job limit. There is no schedule or
background agent restart. The fetcher neither executes SAS reference programs
nor copies them into package implementation. Source bodies remain outside the
package and automatic cache/registry admission. Core parser and annual support
are unchanged by this acquisition increment.

Acceptance requires independent target/availability review, offline preservation
and failure coverage, completed remote manifest inspection and transferred
body/header hash verification. Content/identity inspection is separate from
HTTP success; component joins, missing-reason interpretations, licensed
conversion provenance and author approval require subsequent evidence.
Precommit verification passes 1,966 package assertions, 114 R tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and installed
public workflows. Nine Python cases and an independent 94-attempt probe verify
distinct document bodies/headers, metadata, transfer hashes, fallback and
complete failure receipts. All 23 layout URLs match the official index links;
the 2019 SAS index confirms all four V2 paths. Other annual SAS paths still
need remote content confirmation. Both preliminary reviews found zero blockers;
one wording suggestion corrected the manifest's validation note for non-Core
sources. Clean-head verification, current independent review and hosted checks
remain required before this acquisition increment merges.

The broader acquisition merged in
[PR #32](https://github.com/MSaadAsif/easyNIS/pull/32) after clean-head
verification, current independent reviews with zero blockers and all six
hosted jobs. All 47 references downloaded from the canonical official host.
All 94 transferred body/header hashes and lengths match the remote receipts;
the exact 23-layout inventory matches the original index, and every paired
SAS DATA/INFILE/LRECL identity matches its layout. Programs were not executed.

### Provisional component layout catalog

The next NIS-006 increment shares layout structure validation across Core,
Hospital, Severity and Diagnosis and Procedure Groups, retaining the stricter
Core code-slot checks. An offline updater parses all 23 cached component
layouts before atomically replacing the provisional catalog. Missing or invalid
later files preserve the previous CSV. Source counts, record lengths, field
counts, dataset identities, specification-filename revisions, structural-field
presence, source URLs, MD5 and parse times are retained without synthesizing
absent columns.

The source bodies include YEAR/stratum/weight fields only in Core/Hospital;
Hospital lacks KEY_NIS, while Severity and Diagnosis and Procedure Groups
include both hospital and discharge identifiers. These structural facts do not
authenticate a parquet component join, conversion history or missing reasons.
The runtime consumes neither provisional registry. All 23 generated catalog
identities/counts/lengths/MD5/URLs match a separate Python source inspection.
Invented fixtures cover both guide eras, component identity/type requirements,
absence preservation, offline repeatability and rollback, plus stricter Core
slot rejection through the new updater. Precommit verification passes 1,966
package assertions, 171 R tool assertions (127 layout assertions), all 36
merge-gate scenarios, source Status OK, a 91-entry tarball inspection and
installed public workflows. Independent review matches all 23 source rows,
checks offline CLI output and confirms exact preservation of all six prior
Core parser results. Both preliminary reviews found zero blockers. Clean-head
verification, final review and hosted checks remain required before merge.

The component catalog merged in
[PR #33](https://github.com/MSaadAsif/easyNIS/pull/33) after clean-head
verification, final independent specification/standards review with zero
blockers and all five hosted checks. The next bounded NIS-006 increment audits
cached SAS INPUT assignments and used INVALUE mappings without executing SAS
or inspecting discharge values. All 5,091 assignments across the 23 saved
pairs match layout identities, field order, positions, widths, decimals and
types. Local receipts retain literal missing tokens with year/component/format
keys and both source hashes/URLs; they supply no clinical interpretation or
conversion-preservation claim.

Invented cases cover custom numeric, character and plain numeric informats,
literal special missing tokens, malformed/undefined/duplicate definitions,
identity/position/width/precision/type mismatch, a complete 23-pair batch,
paths with spaces, the real CLI, existing-output preservation and late failure
without partial publication. Shared invented layout fixtures retain the
existing parser cases. Independent review reproduced case-variant declaration
bypasses and quote-insensitive comment removal that fabricated a literal raw
token. Keyword discovery now detects case variants, unsupported format-name
variants fail, and a quote-aware scanner preserves comments/semicolons inside
quoted text while rejecting unterminated constructs. Regressions cover both
findings. The offline tool suite passes 216 assertions without
failures, warnings or skips. Full verification, clean committed-head evidence,
independent review and hosted checks are required before merging this increment.
Corrected precommit verification passes 1,966 package assertions, 216 tool
assertions, all 36 merge-gate scenarios, source Status OK, tarball inspection
and installed public workflows. Independent corrected-source review matches
all 23 pairs, 5,091 fields and 364 literal mappings with zero remaining
blockers; final review must bind the committed head and clean verification.
Next: inspect data-element notes for meanings/units/applicability and obtain
author review; conversion provenance and scientific approval remain separate.

## Foundation and metadata

### Inventory physical field names

A developer-tool regression reproduced SQL name repair changing physical
`field`, `FIELD`, `FIELD_1`, `field` columns into `field`, `FIELD_1`,
`FIELD_1_1`, `field_2`. The NIS-005 inventory now takes top-level names from
the parquet schema, preserving exact duplicates and case collisions. Types
remain DuckDB interpretations in file order; nested descendants do not add
top-level columns. Invented cases exercise differing types, a nested field
followed by another column, positions, counts and the real CLI. The name
assertion fails on the old implementation and all 39 focused assertions pass
after the correction. Precommit Windows verification passes 1,966 package
assertions, 104 tool assertions, all 36 merge-gate scenarios, source Status OK,
tarball inspection and installed public workflows. Independent probes also
cover deep structs, lists, maps, zero-row files, empty names and non-ASCII names.
Clean committed-head evidence, final independent reviews and hosted checks
are required before merge.

At the inventory correction, official source-byte acquisition remained blocked
after alternate-host and browser attempts; the subsequent remote acquisition
above obtained the original references. Annual source contracts, parquet-only conversion
provenance and author scientific decisions retain their existing gates. The
inventory correction changes no annual support or scientific approval.

The NIS-005 codec increment adds `compression_metadata` to the private inventory.
It records distinct column-chunk codecs from parquet footers in sorted order,
separated by semicolons. Declared conversion settings can differ from the
observed codec; neither establishes execution history. Invented Zstandard and
Snappy inputs exercise both the sourceable tool and its CLI, with uncertainty
statuses and the exclusion of discharge values retained. No annual capability
or conversion-preservation status changes. Precommit verification passes 1,966
package assertions, 86 tool assertions, all 36 merge-gate scenarios, source
Status OK, tarball inspection and installed workflows. Both independent
reviewers found zero blockers, including separate empty-file and uncompressed
boundary probes. Clean committed-head verification and hosted checks are
required before merge.

The exact-level fix merged in [PR #24](https://github.com/MSaadAsif/easyNIS/pull/24)
after clean-head verification with 1,966 package and 65 tool assertions,
independent specification/standards reviews with zero blockers and all five
hosted jobs. Resulting main checks also passed.

The NIS-005 inventory follow-up retains the raw parquet footer `created_by`
string as `writer_metadata`. This provides a lead for tracing file creation
without authenticating converter versions, release revisions, joins, filtering
or missing/label preservation. Existing unknown and unverified statuses remain
explicit. Invented-file tests exercise both the sourceable tool and real CLI,
paths with spaces, two file/year-hint cases, footer counts, schema preservation,
unchanged uncertainty statuses and absence of discharge values from receipts.
Precommit verification passes 1,966 package assertions, 81 tool assertions,
all 36 merge-gate scenarios, source Status OK, tarball inspection and installed
workflows. Both independent reviews found zero blockers; a separate probe also
preserves writer strings with commas, quotes, newlines and trailing spaces.
Clean committed-head verification and hosted checks are required before merge.
No private writer metadata or paths enter the public repository. Annual source
snapshots and conversion history remain the next external dependencies.

The quickstart merged in [PR #20](https://github.com/MSaadAsif/easyNIS/pull/20)
with all five reviewed-head and resulting main jobs passing. The next NIS-021
increment adds an installed HTML vignette that executes the same quickstart
with knitr, without Pandoc or network access. It explains the explicit domain,
inference and disclosure policies and displays only reviewed CSV values,
rounded to four decimal places with suppressed cells blank. The source
build/check executes the vignette; installed verification requires discovery,
rendered HTML, blank suppressed cells and absence of temporary source paths.

Initial verification exposed R's generated `build/vignette.rds` index to the
blanket RDS ban. The tarball gate now permits only that exact path with the
exact expected public index object and requires the source, rendered HTML and
extracted code. Five offline cases reject substituted records, private-path
metadata, another RDS and missing HTML while accepting the expected index.
The source check passed with Status OK and 87 tarball entries. The first
installed assertion failed on knitr's padded header text; trimming the headers
corrected it and the installed workflow passed. Full corrected-source
verification passes 1,927 package assertions, 65 metadata/tarball-tool
assertions, all 36 merge-gate scenarios, source Status OK, the 87-entry tarball
inspection and installed workflows. Clean committed-head verification,
independent review and hosted checks remain required before merge.
No annual capability or scientific approval changes.
Integrated pooling/model workflow documentation remains NIS-021 work;
regression-table disclosure/export and annual evidence retain separate gates.

The installed vignette increment merged in
[PR #21](https://github.com/MSaadAsif/easyNIS/pull/21) after clean-head
verification, independent specification/standards reviews with zero blockers
and all five hosted jobs. The next NIS-021 increment integrates six invented
annual designs, explicit average annual pooling, subsequent code-set domain
selection and a Gaussian identity intercept model. Independent hospital WR
arithmetic verifies mean 172/21, SE approximately 0.1993771, average annual
LOS total 4816, variance 106176 and df-12 intervals. The model's intercept/SE
and 288 observed/72 missing outcomes are checked internally. Only reviewed
descriptive values and a fixed declarations/version report are exported;
regression-table disclosure review/export remain unsupported.
The shared invented core builder preserves the single-year fixture. Installed
smoke and the expanded vignette exercise the real scripts, repeatability,
year-specific keys, reference arithmetic, blank suppressed cells and sanitized
reports. Precommit verification passes 1,927 package assertions, 65 tool
assertions, all 36 merge-gate scenarios, source Status OK, an 89-entry tarball
inspection and installed single-year/six-year workflows. Clean-head evidence,
current independent review and hosted checks are required before merge.
Annual metadata, conversion
provenance, licensed validation and scientific/publication approval remain
separate gates, and no annual capability is promoted.

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
| NIS-035 | Add bounded grouped descriptive tables and joint disclosure/export. | 018. | Numeric grouping merged in PR #43 and joint review/export in PR #44, each with all five main checks passing. Completed bounded criterion: exact field/domain count identity for one grouped constructor result, repeated-statistic suppression, independent and cross-group margins/protected sums, hospital unions, group-specific binary/missingness behavior, grouped provenance rejection, ordinary compatibility and installed joint reviewed CSV/HTML/Word exports. No overall rows or between-group tests. |

NIS-033 and the v1 metadata/model safeguards in NIS-034 are release requirements. New scoring algorithms, cost-conversion helpers, and additional model families remain later capabilities with separate validation gates.

NIS-026–030 are later release work, not requirements for the first 2017–2022 release. Paper claims must follow the coverage and behavior of the submitted version.
