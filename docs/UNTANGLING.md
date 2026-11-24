# easyNIS refactor decisions

The audit uses invented fixtures, package source, and Git history. Public signatures, supported inputs, disclosure rules, and statistical assumptions define the behavior to preserve. Comments and test cleanup follow the production changes.

## Read annual files through a single source description

- `R/open-flags.R` couples file discovery to diagnosis and procedure flags. `R/duckdb.R` pairs source paths and optional scans by index, repeats schema inspection, and attaches a temporary query attribute consumed only by open-time name normalization.
- The source description owns the physical schema, quoted scan and nearest partition year. Layout ownership, Hive disagreement precedence, Arrow lifetime, year conversion, and collision-safe output naming remain requirements.

## Give clinical code selection and procedure-day decoding one home

- Flagging, inventory, procedure timing, completeness, comorbidity, and the probe each discover numbered slots. Matching repeats prefix and exclusion rules across backend and feature entry points.
- Timing and completeness encode the same slot pairing and day validity through timing-specific helpers. Schema absence remains distinct from missing decoded days. Timing policy still distinguishes exclusion, day-zero imputation, and indeterminate results.
- Timing scratch names overlook the requested flag name. Completeness assembles empty yearly output with a scalar slot. The layout and name rules should make these cases work without caller workarounds.

## Keep survey and cost policy with the data that defines it

- `R/design.R` repeats design-field names and validity in selection, mutation, grouping, and exclusion reporting. The two lazy scans and the distinction between typed missing and SQL NULL are required.
- `R/design.R:462–488` muffles cost messages and reconstructs cost counts and provenance. Cost adjustment should accept a reporting population so it can count actual cohort records while retaining annual multipliers for all design years.
- `R/cost-example.R` couples CPI adjustment to invented fixture generation. Reweighting reads the design representation and must preserve placeholder rows, transformed variables, and the supported variance structures.

## Make disclosure policy independent of its input format

- `R/suppress.R` calculates discharge and hospital masks separately in data-frame and survey-table paths. The formats share primary policy while complementary masking rules differ.
- `R/suppress-hospitals.R` consumes survey row specifications from `R/suppress.R` and calls private cell-count validation. One survey adapter can own card-to-cell mapping and one hospital identity rule can serve both counting paths. Unsupported or ambiguous card mappings remain fail-closed.

## Give study scaffolding, modeling, and cache invalidation separate responsibilities

- `R/nis-new-study.R` mixes directory creation, report cache dependencies, and survey model diagnostics. Existing studies call three private functions through the generated Quarto document and need compatibility with those names.
- `tests/testthat/test-new-study.R` includes source-spelling assertions for model and cache implementation. Keep the template's actual user-facing guarantees and verify behavior through functions consumed by the template and the render workflow.

## Separate probe policy, evidence handling, and execution

- `tools/probe/helpers.R` mixes workspace safety, Git, study receipts, JSON recovery, quality records, and package metadata inspection. The scripts need explicit modules for these concerns and stable receipt semantics.
- `tools/probe/probe-quality.R`, `provenance.R`, and `readiness.R` repeat check identifiers and levels of trust. A check's metadata should travel with the check definition. Malformed or unverified evidence must continue to fail closed.
- `tools/probe/probe-real-data.R` uses global assignments and step-name switches to assemble outcomes, timing, and private diagnostics. Producers should declare what they capture and return each result to the caller. All outputs stay inside the verified ignored directory.
- `tools/check-no-private-data.R` lists index paths but reads worktree bytes. The hook should inspect the blob that would be committed. `.Rbuildignore` also registers `codemeta.json` twice.

## Keep large Parquet work inside DuckDB

- The previous annual reader validated every physical year column by scanning and casting it. An integer column whose type fits the result already satisfies the whole-number and range rules. Hive integer comparisons can use the stored column and Parquet statistics.
- Compatible consecutive parts can share one native Parquet scan. Keep separate projections when schemas or partition years differ so each source retains its year and type checks.
- Code inventory generated an intermediate row for every distinct code before testing prefixes. Filter each discharge's code list before expanding it and collect the grouped counts.
- Give open queries owned spill directories and expose DuckDB's workload settings. Release the connection and its spill directory together. Real-data probes place spills in the verified private run directory. A collected survey design needs enough R memory for the retained cohort.

## Regressions covered with invented fixtures

- A nested Hive part follows the nearest selected partition.
- DuckDB analysis fields cannot shadow reserved names by ASCII case.
- Malformed survey count cards fail closed before masking.
- Diagnosis and procedure helpers keep their input fields and return typed empty summaries.
- Integer64 attrition and reweighting preserve counts and usable survey weights.
- Generated studies normalize relative scaffold paths, include reference tables in cache keys, and use factor levels present in complete cases for model preflight.
- The privacy guard sees the exact staged blob even when a different worktree copy exists.
