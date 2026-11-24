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

## Architecture audit at `b3c72ad`

The second audit covered package entry points, the generated study, probe
commands, CI, and the project verification skills. The following decisions
record the source layout at the start of this pass.

### Plan Parquet scans and retain their sources in one module

- `R/open.R:115–123` validates each part before `R/open-parquet.R:81–98`
  groups compatible consecutive parts. Bind and validate the scan groups
  first, then use those groups to read data. On a validation failure, identify
  the offending parts using the same predicate. Keep per-part schemas because
  the native reader and the Arrow adapter can expose different types.
- Wide integer years need a range check. Use native integer bounds to let
  DuckDB discard valid row groups from Parquet statistics.
- `R/open.R:147–152,203–222` visits nested directories for discovery and
  revisits them through each selected parent. Give each part an explicit owner
  and retain its selected path. Preserve nearest Hive ownership, physical
  `YEAR` checks, literal paths, and stable output column spelling.
- `inst/templates/nis-study/analysis.qmd:66–70` requests cache metadata for
  every Parquet file under the input root. Use the selected paths from the
  opener so an unrelated file cannot force an expensive rebuild. Keep the
  cache helper interface already used by generated studies.
- The same template passes the raw cache payload to knitr, which can put
  package source and private paths into HTML chunk attributes. Use a digest
  as the rendered cache key and verify explicit input paths stay out of HTML.
- `tools/probe/probe-real-data.R:16–20` recognizes only annual filenames.
  Give the probe the opener's discovery result and cover mixed layouts.

### Collect a compact description of the survey sample

- `R/design.R:85–126` groups invalid records on raw hospital and stratum
  IDs and transfers those groups to R, although exclusion reporting uses
  only the defect flags and usable year. Group by IDs only for valid rows.
- `R/design.R:202–222,394–400` reads the valid sample again solely to
  check which quarters are present. Add bounded quarter indicators to
  the sample summary, keeping the distinct 2015 cohort diagnostic.
- `R/design.R:180–199` collects missing-cohort rows only to count them.
  DuckDB R 1.5.2 slices an already materialized DBI result. A SQL window or
  materialized CTE can shrink the result sent to R while buffering the
  candidate rows in DuckDB, and an extra scan would reevaluate the cohort
  expression. A temporary counter would add connection state and depend
  on optimizer evaluation order. Keep once-only evaluation and discard
  missing rows before constructing the survey object. The retained cohort
  still requires R memory.

### Validate code audit inputs in the summaries that already read them

- `R/code-audit.R:40–52,420` reads the whole eligible input to check
  weights separately from each audit's period summary. Aggregate validity
  with the denominators and preserve period rows when there are no code matches.
- `R/dx-sensitivity.R:150–172` has a separate missing-value rule from
  `R/attrition.R:145–149`, so DuckDB NaN can corrupt weighted counts and
  mortality. Reuse the backend missing-value rule and keep the two analyses'
  distinct statistical semantics.
- Move column names, identifier allocation, missing-value expressions and
  collection to `R/query-expressions.R`. Those are query operations.
  `R/duckdb.R` owns connection and temporary-storage lifecycle.

### Visit each disclosure stratum once

- `R/suppress-data-frame.R:99–108` repeatedly scans all row groups to
  find one stratum's rows. Use the rows already produced by grouping.
  Preserve primary precedence, positive counts, tie order, and isolation
  across strata. The bounded disclosure check covers all these cases.
- `R/cell-counts.R:1–8` and the getting-started vignette require
  collecting all discharges before counting. Give DuckDB an adapter
  that counts the same year-scoped hospitals and validates each identity
  in the aggregate. The disclosure interface should collect only cell counts.

### Put study cohort flow and render verification behind their own interfaces

- `inst/templates/nis-study/analysis.qmd:165–181` scans the Parquet
  query independently for baseline, principal diagnosis, and cohort totals.
  Summarize all three in one statement. Keep the criteria independent so
  custom cohorts need not be subsets of the principal diagnosis.
- `.agents/skills/verify/drive.R:122–153` and
  `.github/workflows/template-render.yaml:29–59` drive the same
  public study interface independently. Share the installed journey, keeping
  built-in inputs and explicit inputs as separate cases. Use rendered output
  to check the scaffold promises where tests currently match source text.
- The independent render review found exact cohort and hospital counts
  in Methods even when cohort flow masks the same small cohort. Use the
  same disclosure display rule in both places. Check the rendered
  rare-cohort report and its supporting assets.

### Reuse a writer for each invented fixture

- `R/example.R:144–170` opens a new DuckDB instance for every annual
  file through `R/duckdb.R:104–115`. The fixture operation should own one
  writer, one temporary table at a time, and its destination until the
  annual files have been written successfully. Tests that write one Parquet
  part can still use the same writing operation.

### Build the package check from committed source

- On Windows, `R CMD build` can copy the checkout before applying
  `.Rbuildignore`. A concurrent verification held an ignored evidence file
  open and caused the build copy to fail. Run qualification from an exact
  Git snapshot in temporary storage so local datasets and evidence never
  enter the build copy.
