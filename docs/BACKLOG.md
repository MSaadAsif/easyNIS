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
