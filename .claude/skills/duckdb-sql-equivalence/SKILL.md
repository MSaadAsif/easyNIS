---
name: duckdb-sql-equivalence
description: Check easyNIS DuckDB SQL against independent R references and prove the Taylor, grouped IRLS, slot, and resource-lifetime models in Lean 4.
---

# DuckDB SQL equivalence

For the stated bounds, a DuckDB builder must return the same result as its
independent row-level reference on the same invented records. A change in
code matching or aggregation can silently change a cohort, estimate, or
standard error.

Install [elan](https://github.com/leanprover/elan/blob/v4.4.0/README.md),
put its bin directory on PATH, and install the pinned toolchain with
`elan toolchain install leanprover/lean4:v4.26.0`. The
[Lean project](../../../tools/formal/duckdb/) has no external packages.
Run from the repository root with the usual R development dependencies.

```sh
Rscript --vanilla tools/formal/duckdb/run.R
Rscript --vanilla tools/formal/duckdb/run.R --mutations
```

The first command runs `lake build DuckDBProofs` and the real-SQL harness.
The second also requires the scratch Lean variants to produce proof errors
and the real-SQL mutations to change their outcomes. Add `--lean-only` to
run only Lake. To check one SQL builder, use
`Rscript --vanilla .agents/skills/duckdb-sql-equivalence/check.R <builder>`.
The R runner loads package source from the checkout and executes the actual
queries in DuckDB. It writes tool versions, the source commit, the command,
batch counts, and any mismatches to the printed directory under
`local/loop/`. Counterexample RDS files contain the configuration, invented
input rows, expected output, actual output, and the first mismatch. For
example, `readRDS(path)$result` gives the two outputs and the differing field.
Fixtures regenerate with seed 243. Counts, flags, assignments, and missing
values compare exactly. Selected numeric estimates and standard errors use
an absolute tolerance of 1e-12.

`--mutations` in the SQL runner checks the baseline, replaces one function in the loaded
namespace with a scratch edit of its source, runs the real query, restores
the binding, and checks the baseline again. The working tree stays intact.
A syntax error or unexpected execution failure cannot kill a mutation.
`MUTATION CAUGHT` requires an outcome mismatch on a baseline-passing batch.
A surviving or stale mutation means the qualification is incomplete.

A finding is an output that breaks the documented property. Check the
fixture types and the public contract before changing a reference or
normalization. Keep a genuine failure and its input in the local evidence
and report it. An error in the fixture or reference should be corrected in
the harness. Use `/maintain-formal-verification-skill` to reconcile this
coverage after a change that lands without a rerun.

## SQL coverage

The product source sync commit is `7a73cc89db95a362d09e0df346d0355d04bf016e`.
The reference run uses R 4.6.1, DuckDB 1.5.2, dbplyr 2.5.2, and survey 4.5.
Here is what each registration exercises.

| Builder | Production paths | Declared bound and mutation |
| --- | --- | --- |
| `code-flags` | `R/code-flags.R:nis_code_flag_exprs, nis_code_match, nis_sql_match` and `R/code-layout.R:code_system_filter, code_system_valid_year` | Two diagnosis slots per system, five code values per slot, three positions, both single systems and mixed, eight year values, six quarters, five version values. Drop the match from the second slot. |
| `prday-timing` | `R/pr-timing.R:timing_flag_system, timing_index_day, timing_result` and `R/procedure-days.R:nis_decode_procedure_day` | Two slots per system, three code and eight day values per slot, three years, three quarters and versions, all relations and missing-day policies, window 1. Also a missing third PRDAY column and 512 generated 25-slot records. Decode fractional days as integers. |
| `code-inventory` | `R/code-audit.R:.nis_audit_lazy_codes` | Two slots with five code values, two years and three weights. Keep duplicate codes when unnesting the slot list. |
| `ccsr` | `R/ccsr-query.R:nis_add_ccsr, ccsr_release_sql, ccsr_mapping_filter, ccsr_query_sql, ccsr_mapping_joins` | Up to two slots and eight code values, eight years, six quarters and three versions. Diagnosis and procedure categories, diagnosis defaults, pinned and unpinned 2025.1, and a category filter. Keep duplicate category assignments. |
| `comorbidity` | `R/comorbidity.R:nis_comorbidity_lazy` and `R/comorbidity-sql.R:nis_cmrb_inputs, nis_cmrb_validate_keys, nis_cmrb_score_sql` | Bundled FY2027 Elixhauser, one principal and two secondary slots, capped fiscal year and Q4 transition, five POA values per secondary slot, chosen hierarchical and POA-sensitive codes. Drop POA `W` from positive evidence. |
| `design-sample` | `R/design-sample.R:nis_design_sample, nis_sample_group_rows, nis_design_collect_cohort` | All declared combinations of valid or invalid design identifiers and weights, five quarters and three cohort states, with valid hospitals in two years. Use maximum hospital weight in place of minimum. |
| `attrition` | `R/attrition.R:nis_attrition, .nis_attrition_keep_exprs, .nis_attrition_summary_exprs` and `R/code-flags.R:nis_code_criterion_exprs` | Two cumulative criteria, missing criteria and weights, with and without design exclusion, with and without year grouping. Combine criteria with OR. |
| `cell-counts` | `R/cell-counts.R:nis_hospital_count_query` | Three hospital IDs reused across two years and three cell values, including missing. Count hospital groups in the discharge column. |
| `annual-totals` | `R/trends.R:nis_annual_totals, nis_annual_summary` | Two sampled hospitals and four quarters per year. All 81 assignments of true, false, or missing to four discharges. Give excluded discharges nonzero weight. |
| `survey-aggregate` | `R/lazy-survey.R:nis_survey, nis_survey_variance` and `R/lazy-survey-stat.R:nis_survey_aggregate, nis_survey_scores, svyby.nis_survey` | The same four-discharge domain bound, with numeric outcomes including missing, pooled and grouped means and totals. A separate fixture covers a sampled singleton, a domain singleton, and an empty stratum with domain adjustment on and off. Include out-of-domain records in the SQL aggregate. |
| `survey-irls` | `R/lazy-survey-glm.R:nis_survey_model_input, nis_survey_model_system, nis_survey_irls, nis_survey_model_variance` | Grouped-row quasibinomial and Poisson fits, two strata, three PSUs per stratum, three covariate values and unequal weights. Average grouped weights in place of summing them. |

The registration source gives the exact finite alphabets and generated
draws. SQL executes for every element of each declared Cartesian product.
The estimates use invented annual Parquet for the lazy survey entry point.
The CCSR reference reads the bundled lookup as raw data and does the matching
and release filtering in R. The Taylor reference uses explicit score sums
in R and independent row-level `survey` for non-removable missing outcomes.
The GLM reference uses row-level `survey::svyglm()`. The Parquet planner
and disclosure masking already have their own skills.

Each registration also declares the transformations it can meaningfully
check. Slot tests swap paired code, day or POA positions together. For
diagnosis flagging the first-slot and second-slot results exchange when
the inputs exchange. Year tests concatenate year-local results. Domain
tests add excluded records to existing PSUs and compare both the estimate
and SE. Reversing row order must preserve the result after ordering by its
semantic keys. Pooled survey means and GLM coefficients require a joint
estimator, so their separately fitted coefficients are outside the
year-concatenation relation.

## Lean proof coverage

The algebra is over exact rationals. Lean checks induction on lists whose
lengths are arbitrary. Lifetime proofs use induction on arbitrary finite
traces of the modeled operations. The scratch runner changes definitions
while leaving their claims in place, checks for Lean proof errors, and
rebuilds the original model.

- Taylor means and covariance. The score identity removes the SQL mean
  anchor exactly. The fold base and step prove the centered cross-product
  identity for any finite number of active PSUs. The padding step gives
  the contribution of every absent sampled PSU. The symbolic sampled count
  verifies the scale, active-stratum grand center, sample singleton and
  domain singleton branches of `survey` 4.5 `onestage()` and `onestrat()`.
  `taylorVariance` checks the result pooled across every finite list of
  strata, including the `fail` outcome for sampled singletons. This models
  the inputs produced by `nis_survey_aggregate()` and
  `nis_survey_scores()` and the roster supplied by `nis_survey_variance()`.
  It assumes one-stage sampling with no finite population correction,
  calibration, or missing score components. Empty strata contribute no
  score or sampled count to the grand center. A mutation drops padding,
  and others change centering or singleton handling.
- Grouped IRLS. With fixed coefficients after the initial row-level step,
  identical normalized predictors and outcomes share eta, derivative,
  working response, and unit deviance. The base and one-row step give
  identical X'WX, X'Wz, and deviance for every finite grouping with
  positive finite weights. This models `nis_survey_irls()` and
  `nis_survey_model_system()`. The mutant ignores an observation's weight.
- Slot folds. Given the same predicates for each slot and retained
  code/day/POA pairing, the empty and one-slot steps give equivalent
  existence and earliest-known-day folds for any number of slots. The
  POA step models eligibility for positive evidence with an exemption or
  an unrestricted condition and excludes the principal diagnosis.
  This refers to `nis_code_match()`, `timing_index_day()`,
  `nis_decode_procedure_day()`, and `nis_cmrb_score_sql()`. It covers
  the algebra for a future UNPIVOT path. The code predicates, SQL null
  handling, negative evidence, and physical slot pairing still need
  independent checks on the actual implementation.
- Lazy query lifetime. `Query.ownership` and `liveQuerySafe` establish that
  a live handle can collect only with a live connection and, for computed
  handles, a live private table. The model starts at the successful owner
  handoff in `R/open.R:nis_open`. It models ownership in
  `R/duckdb.R:nis_duckdb_attach_finalizer`, `compute.tbl_nis` and
  `nis_duckdb_open_data`, source retention in
  `R/ccsr-query.R:nis_add_ccsr` and
  `R/comorbidity.R:nis_comorbidity_lazy`, and collection in
  `R/collect-prudence.R:db_collect.nis_duckdb_connection`. The #198
  mutation drops the computed query's owner. The modeled trace then drops
  the source, disconnects, and leaves the computed query unable to collect.
  The cleanup theorem shows the finalizer path is available once all
  owners are gone. It assumes the finalizer is invoked and native cleanup
  succeeds.
- Scoped cleanup. `Scoped.registeredCleanup` covers both successful return
  and an error that unwinds a call. It assumes acquisition either fails
  resource-free or reaches the registered `on.exit`, and that the handler
  completes. The modeled resources are the grouped-row temp table in
  `R/lazy-survey-glm.R:nis_survey_irls`, the conversion batch registration in
  `R/convert.R:nis_convert_copy_batch`, the private connections in
  `R/comorbidity.R:nis_comorbidity_frame` and
  `R/ccsr-query.R:ccsr_bundled_codes`, and the spill directory in
  `R/duckdb.R:nis_duckdb_open_data`. A spill transferred to its caller
  follows the connection-owner model.
- Atomic publication. `Writer.publicationSafe` and `previousTargetPreserved`
  cover any number of staging increments, with one writer and synchronous
  COPY. A prior target survives, a published target has the validated
  count, and the rename cannot be attempted while a validation handle is
  open. `registeredWriterCleanup` checks that closing the private database
  comes before removing the stage on error, with no resources left on a
  successful or guarded error exit. Code paths are
  `R/convert.R:nis_convert_with_stage`, `nis_convert_stage`,
  `nis_convert_check_count`, `nis_convert_publish`,
  `R/write-cohort.R:nis_write_cohort`, `nis_cohort_copy_parquet`,
  `nis_cohort_check_count`, and
  `R/duckdb.R:nis_remove_owned_directory`. The model assumes the OS
  supports same-parent atomic rename, stage COPY releases borrowed handles
  before returning, and native close and unlink succeed.

The lifetime model exposes three reachable registration gaps if R can
unwind after acquisition and before arming cleanup. A scoped resource, a
staging directory, or a private writer connection can survive the call.
Lean checks each counterexample trace. The writer's target remains safe
even when these gaps are allowed. These are ordering findings in the
model, without a forced R interruption replay.

The proofs cover formulas and a state-machine design. The bounded R
harness guards the actual DuckDB SQL text and floating-point execution.
The differential bounds exclude arbitrary schemas, all mapping versions
and methods, all RE2 patterns, arbitrary model formulas, and licensed
records. The lifetime model leaves out concurrent writers, external
disconnects, Arrow lifetimes, process termination without R unwind,
failed native cleanup, and filesystem durability after rename.

## Register a builder

1. Add a file under
   [.agents/skills/duckdb-sql-equivalence/builders](../../../.agents/skills/duckdb-sql-equivalence/builders/).
   Give it a stable name, exact `file:function` coverage, and a declared
   bound. List the result-changing failure modes before selecting fixtures.
2. Register `register(name, cases, sql, reference, mutation, relations, ...)`.
   `cases(con)` returns `case(rows, args)` values. Use `fixture()` for
   Cartesian products and seeded draws. Keep original wide rows even if
   production transposes them. Make every registered path run on an
   invented input through its normal entry point or call its real internal
   builder if the public output would hide the SQL result.
3. Write `sql(con, rows, args)` and `reference(rows, args)` to return the
   same columns in the same order, sorted on semantic keys. Use the package
   only on the SQL side. Keep the oracle in plain R or use an independent
   estimator for numerical checks. Preserve nulls, duplicate rows, and
   missing results. Declare `approximate` only for floating-point outputs.
4. In `relations`, name the applicable transformations. Each function
   receives a case and returns lists of cases as `left` and `right`, and
   optionally a `combine(outputs)` function. The default concatenates
   outputs and orders by `id` when present. Use `relation_case` to choose
   a small witness with meaningful changes. Add a `relation_mutations`
   entry to demonstrate that a new relation detects a semantic break.
5. Supply `mutation(file, function_name, from, to)` with a unique source
   expression or SQL fragment in the deparsed function. Change a result
   while keeping the query valid. Run both commands and review the
   counterexample for the mutation. For a changed Lean proof, run the
   combined command with `--mutations` and inspect the proof errors.
6. Record affected paths, bounds, observed outputs, and platform. Advance
   the sync commit only after checking the package paths, proof assumptions,
   and clean and mutated outcomes against the new product source.

The next target is the post-#243 native PRDAY rewrite. Reuse the timing
registration with its two-slot oracle and 25-slot draw, then move the
scratch mutation to the new SQL builder and add any changed PRDAY schema
rules to the finite domain.
