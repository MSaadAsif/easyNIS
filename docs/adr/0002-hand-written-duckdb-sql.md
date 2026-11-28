# 0002. Shorten easyNIS's path to DuckDB

## Status

Proposed for the DuckDB port series.

## Context

A lazy call can spend time building and rendering R expressions, preparing SQL,
scanning data, checking output safety, or transferring results back to R. Those
costs require different fixes. The current timing path builds three stacked
mutations. CCSR and comorbidity already use hand-written SQL for their main
operations. Their scan and join costs remain even when the R translation is
eliminated. The survey engine in [ADR 0001](0001-in-database-survey-estimation.md)
already leaves the row-level work in DuckDB.

## Decision

Keep the user-facing dplyr/dbplyr API. Render the caller's upstream lazy query
where it enters an easyNIS operation and return composable lazy tables with
`dbplyr::sql()` and `dplyr::tbl(con, sql, vars = ...)` when a port needs them.
Carry the source lifetime, metadata, grouping, and column names across that
boundary. Use one SQL builder per operation. Quote identifiers with
`DBI::dbQuoteIdentifier()` and bind values whenever the execution API supports
parameters. For lazy SQL, escape literal values through DBI and never insert raw
values into SQL text. DuckDB-specific SQL is acceptable. Use a macro only when
it removes measured work and keeps the operation independently testable.
Keep dbplyr for paths where its cost does not justify a port.

Register each SQL builder in the bounded-exhaustive R harness before merge.
Use Lean 4 for proofs of the operation's semantics and algebraic properties.
Separately, run the emitted SQL on DuckDB through the R harness and compare
its results with an independent plain-R reference. Cover slot, position, coding system,
missingness, sentinels, and era in the bounded search space.
Exercise slot permutation with paired day and POA fields where position is
immaterial, year split-and-union for row-level results, and row-order
invariance where order is immaterial. For added out-of-domain rows, check the
point estimate and compare the variance with the R reference on the changed
PSU roster. Add seeded randomized cases and record at least one deliberate
mutation that the harness rejects. Survey changes must agree with `survey`
within `1e-12` on invented data and preserve licensed-data
[criterion 7](../IMPROVEMENT-ROADMAP.md#ready-criteria). Retain the existing
error, release, survey-design, memory and disclosure contracts while changing
how they are enforced.

## Consequences

Gate each demonstrated performance gain in CI with an invented workload,
an output check, and a budget for the phase that improved. Also keep an
end-to-end time or memory budget where the caller sees the gain. Establish
thresholds from repeat runs on CI hardware, with enough headroom for runner
variance. At the end of the port series the owner runs one read-only field-test
study at the 8 GB profile and retains time and memory only.

## Measurements

The baseline is `5761901a`, measured on Windows x64 with R 4.6.1, DuckDB 1.5.2,
dplyr 1.2.1, and dbplyr 2.5.2. The fixture has five annual Parquet files with
500,000 invented rows each, 139 columns, 40 diagnosis slots and 25
procedure/day pairs. It uses repetitive synthetic codes and hospital IDs.
The annual files omit the non-release marker to exercise the release scan.
The profiles use 4 DuckDB threads and a 4 GB buffer limit, then 8 threads and
an 8 GB buffer limit. Buffer limits do not cap the R heap or process commit.
Each row uses a fresh R process. The filesystem cache is shared, and some
local runs overlapped. The timings are single instrumented observations
unless a comparison says otherwise. Treat close results as inconclusive.

### Entry points and current call paths

<!-- MEASURED BASELINE START -->

Each cell reports elapsed seconds (other R / render / prepare / execute and
fetch), then statement count / data scan operators / full pooled scan operators,
then peak process commit in MiB. A full pooled scan is an operator reading
all five fixture files with a scanned-row counter of at least 2.5 million.
Reference, staged and per-file scans still count as data scans. Statement counts
come from DuckDB's query log. The driver records total peak commit during process
startup, prerequisites and the call; the measured time starts at the call.
Lazy results were forced by a scalar reduction using every measured output.
The bundled CCSR code lookup uses its own single-thread connection.

| Workload | 4 threads / 4 GB | 8 threads / 8 GB |
| --- | --- | --- |
| Open, native | 2.42 (0.66/1.36/0.08/0.31); 10/1/1; 368 | 4.26 (1.44/2.28/0.14/0.40); 10/1/1; 369 |
| Open, release check off | 2.91 (1.18/1.55/0.07/0.11); 7/0/0; 364 | 2.57 (0.69/1.69/0.07/0.12); 7/0/0; 364 |
| Open, Arrow | 3.22 (2.26/0.00/0.12/0.83); 10/5/0; 636 | 4.66 (3.79/0.00/0.24/0.62); 10/5/0; 534 |
| DX prefix flag | 5.26 (0.55/3.24/0.10/1.37); 3/1/1; 414 | 5.58 (0.72/3.74/0.11/1.01); 3/1/1; 444 |
| PR regex flag | 4.33 (1.01/2.54/0.08/0.71); 4/1/1; 398 | 4.03 (1.04/2.43/0.08/0.48); 4/1/1; 419 |
| Procedure timing | 24.56 (2.95/15.88/0.45/5.27); 3/1/1; 452 | 22.01 (4.03/14.30/0.30/3.39); 3/1/1; 527 |
| CCSR any, one category | 279.73 (0.32/1.09/0.31/278.00); 4/3/1; 2535 | 187.91 (0.32/1.10/0.29/186.20); 4/3/1; 4382 |
| CCSR principal default | 2.66 (0.47/1.79/0.07/0.32); 3/2/1; 393 | 2.47 (0.39/1.74/0.07/0.27); 3/2/1; 401 |
| CCSR code lookup | 0.42 (0.34/0.00/0.01/0.06); 2/2/0; 376 | 0.57 (0.47/0.00/0.02/0.09); 2/2/0; 376 |
| Outcomes | 5.44 (1.53/3.23/0.12/0.55); 3/1/1; 389 | 2.43 (0.58/1.58/0.07/0.21); 3/1/1; 397 |
| Comorbidity, Elixhauser HF projection | 33.61 (17.46/1.25/1.64/13.26); 4/3/3; 1015 | 31.61 (14.90/1.90/3.30/11.50); 4/3/3; 1110 |
| Attrition | 2.85 (0.68/1.89/0.08/0.20); 3/1/1; 390 | 3.91 (1.05/2.46/0.13/0.26); 3/1/1; 394 |
| Design, sample and cohort | 5.93 (1.34/3.65/0.20/0.74); 9/2/2; 401 | 8.93 (2.20/5.77/0.24/0.72); 9/2/2; 411 |
| Design, saved cohort | 5.86 (2.74/2.81/0.15/0.16); 9/2/0; 397 | 6.34 (2.67/3.40/0.10/0.18); 9/2/0; 412 |
| Survey mean | 5.32 (0.44/3.69/0.13/1.07); 5/3/3; 394 | 3.80 (0.39/2.76/0.11/0.54); 5/3/3; 424 |
| Survey grouped mean | 5.53 (0.51/3.56/0.14/1.32); 6/4/4; 400 | 5.52 (0.58/3.72/0.13/1.09); 6/4/4; 429 |
| Survey quasibinomial GLM | 10.15 (1.12/4.29/0.40/4.34); 16/6/6; 401 | 6.77 (0.99/3.02/0.24/2.52); 16/6/6; 430 |
| Annual totals | 8.44 (2.18/5.01/0.20/1.05); 9/2/2; 396 | 11.88 (3.03/7.61/0.27/0.98); 9/2/2; 418 |
| Cell counts | 3.87 (1.02/2.53/0.08/0.24); 4/1/1; 392 | 2.99 (0.91/1.84/0.08/0.16); 4/1/1; 406 |
| Suppress grouped cells | 0.01 (0.01/0.00/0.00/0.00); 0/0/0; 385 | 0.07 (0.07/0.00/0.00/0.00); 0/0/0; 405 |
| Write cohort | 10.85 (2.27/7.06/0.25/1.28); 9/3/2; 397 | 8.74 (1.41/6.37/0.17/0.79); 9/3/2; 420 |
| Convert SPSS, one year | 152.95 (141.39/0.00/0.09/11.47); 17/0/0; 1388 | 76.31 (69.06/0.00/0.05/7.20); 17/0/0; 1386 |
| PRDAY audit | 59.31 (19.19/31.15/1.81/7.17); 3/1/1; 485 | 49.05 (13.13/29.04/1.76/5.12); 3/1/1; 568 |
| DX position audit | 13.03 (5.84/4.68/0.27/2.24); 3/1/1; 437 | 11.43 (3.43/6.05/0.30/1.65); 3/1/1; 492 |
| Code-transition inventory | 8.22 (0.84/2.98/0.13/4.27); 8/2/2; 456 | 8.96 (1.33/4.48/0.19/2.97); 8/2/2; 522 |
| Code-transition counts | 4.01 (0.63/2.18/0.10/1.09); 5/1/1; 424 | 4.79 (1.04/2.82/0.12/0.82); 5/1/1; 460 |
| Public compute, three columns | 0.36 (0.07/0.02/0.02/0.24); 2/1/1; 427 | 0.40 (0.10/0.08/0.03/0.19); 2/1/1; 426 |
| Collect, three columns | 0.61 (0.04/0.03/0.03/0.51); 4/3/2; 519 | 0.96 (0.08/0.05/0.06/0.76); 4/3/2; 525 |

<!-- MEASURED BASELINE END -->

| Entry point | easyNIS-to-DuckDB path |
| --- | --- |
| `nis_open()` | Discover files in R → open private spill directory and connection → per-part `DESCRIBE` and year validation → grouped native `read_parquet` or explicit Arrow registrations → release-marker and row-count footers, projected release aggregate → saved-cohort footer → dbplyr name normalization and source render → attach provenance and finalizer. |
| `nis_flag_dx()`, `nis_flag_pr()` | Discover slots from lazy column names → validate definition and coding-era eligibility → emit prefix/exclusion and regex expressions into dbplyr `mutate()`. Regex validation uses bound DuckDB RE2. A data-frame regex path uploads distinct values into a temporary DuckDB table. |
| `nis_flag_pr_timing()` | Validate rules and slot pairs → dbplyr projections for slot matches, day normalization, minimum index day and relation/missing-day policy → render projected flag when consumed. Shared PRDAY helpers also feed `nis_audit_prday()`. |
| `nis_add_ccsr()`, `nis_ccsr_codes()` | R release manifest → optional category-validation query on reference Parquet → raw SQL renders the input and joins a mapping per slot → lazy table with explicit variables. Bundled code lookup opens a short-lived connection and reads category and code tables directly. |
| `nis_outcomes()` | Lazy names and R argument checks → a dbplyr projection for normalized death, length of stay and discharge disposition. |
| `nis_comorbidity()` | Validate slots and scoring specification in R → render narrowed source and code-system eligibility → direct key/eligibility aggregate → raw lookup, slot expansion, aggregation and score decoding → dbplyr join back to source by validated keys. Frame inputs register a narrowed R frame, collect scores and attach them in R. |
| `nis_attrition()` | Translate caller criteria and easyNIS-generated validation, cumulative criteria and conditional counts into dbplyr → collect grouped counts through the preflight → compute weighted percentages in R. |
| `nis_design()` | Zero-row R prototype for tidyselect and quarter types → dbplyr grouped sample roster, invalid records and weights → cohort type query, projected cohort scan and preflight → collect cohort rows plus grouped roster → R type handling, aliases, placeholders and survey construction. Saved cohorts use stored membership and keep hospital placeholders. |
| `nis_survey()` and estimators | Validate names and provenance in R → lazy valid-design filter → render formula/domain projection → raw schema, factor/group levels, PSU roster and grouped sums → R Taylor variance. GLM uses raw scale/Gram/IRLS/variance passes and a conditional compressed temporary table. |
| `nis_annual_totals()` | Design-field and coding-era validation → grouped sample roster → optional 2015 quarter query → dbplyr PSU domain totals → collect aggregates and calculate variance in R. |
| `nis_cell_counts()` | Validate grouping via lazy names → raw projected key `DESCRIBE` → nested dbplyr hospital/cell aggregation with an invalid-ID flag → guarded collect → R arrangement. |
| `nis_suppress()` | Tidyselect and suppression in R from counts, hospital support or survey cards. DuckDB work occurs when producing the upstream counts; the suppression call has zero SQL statements. |
| `nis_write_cohort()` | Tidyselect prototype and cohort-type check → partitioned buffer setting query and scoped override → render and `COPY` patients → read staged hospital keys against full-sample hospital roster → second `COPY` for placeholders → verify counts from final footers before publication. |
| `nis_convert()` | Stage output and set source order. Statistical files use Haven batch reads and R validation → register each frame → direct Parquet `COPY` → unregister → footer-count verification and publication. Fixed-width ASCII uses a separate source-format validation pass and direct DuckDB decode/`COPY`. |
| Supporting queries | `nis_join_companion()` probes and validates keys then lazy-joins a projected source. Code-transition and diagnosis-position audits translate grouped counts; the inventory uses raw list expansion. Generated-study reporting uses a dbplyr opening count and a combined flow summary. `compute.tbl_nis()` preserves ownership after dbplyr materializes a query. |

### Port order and layer decisions

1. **CCSR category presence.** Prototype a category-restricted query first,
   using one version-aware mapping lookup and a list membership test. The
   existing any-position operation repeats the release and mapping join across
   all 40 slots. The single-category prototype reads the same bundled mapping
   and checks all 40 slots in one pass. This was the largest observed
   improvement. The comparison covers one category, release and consumer.
   Preserve covered-empty versus
   out-of-coverage missing results, list ordering, principal/default semantics,
   and support for arbitrary input queries. Measure the unrestricted
   category-list operation separately before selecting its shape.
2. **Procedure timing and shared slot matching.** Port the wide timing kernel
   and reuse its DBI-quoted matcher for flags if their own end-to-end results
   justify it. The controlled trial saved 14.97 s of median preparation across
   the combined timing and flag pipeline. Keep timing intermediates lazy. Keep
   distinct passes for slot match/day decoding, index-day reduction, and the
   final relation where this protects DuckDB and dbplyr from expression
   duplication. An `UNPIVOT` comparison caught loss of indeterminate results
   when a non-NULL procedure had a NULL day. The PRDAY completeness audit also
   spends heavily in rendering and should exercise the shared day decoder in
   its own comparison.
3. **Comorbidity lookup construction and score join (evaluated).** Retain the
   existing score builder. At `cee1db00`, three fresh runs per method and
   `count_distinct` setting used three invented annual Parquet files per
   coding era, each with 500,000 discharges. The runs used DuckDB 1.5.2 on
   Windows x64 with four threads and a 4 GB buffer limit. With all added
   columns reduced to a scalar result, median wall times with distinct
   counting off and on were 16.41 and 14.13 s for Refined Elixhauser,
   21.85 and 22.68 s for mixed-era Quan Charlson, and 12.09 and 13.07 s
   for ICD-9 Deyo. R scoring-spec setup took 5.30–7.39 s, mostly loading
   medicalcoder on first use. Lookup SQL construction took 6–25 ms.
   Translation, rendering and DuckDB preparation accounted for 7.3–9.2%
   of wall time. Median peak process commit ranged from 926 to 1,216 MiB.
   A replay with shorter slot tests reduced the median
   scored query from 10.19 to 7.83 s for Quan and from 3.19 to 2.50 s for
   Deyo, equivalent to about 11% and 6% of their full calls. The paired
   replay profiles reported 574 and 576 MiB of peak DuckDB buffers for Quan
   and 289 and 402 MiB for Deyo. These gains fall short of the 20% end-to-end
   threshold used for this port.
4. **Design, annual totals and cohort export (evaluated).** Port the
   internal validity, roster, cohort projection and PSU aggregate queries.
   Translate caller criteria with dbplyr and reuse the rendered input when
   preparing the export schema and rows. Relative to `ebe6eeed`, three
   alternating fresh runs per workload used five invented annual files of
   500,000 rows each on Windows x64 with DuckDB 1.5.2, four threads and a
   4 GB buffer limit. Baseline rendering and preparation accounted for
   54–67% of wall time across the workloads, above the 20% threshold.

   | Workload | Wall (s) | Render + prepare (s) | DuckDB execution (s) | R result transfer (ms) | Peak process commit (MiB) |
   | --- | ---: | ---: | ---: | ---: | ---: |
   | Design from annual sample | 4.06 → 2.53 | 2.61 → 1.22 | 0.530 → 0.559 | 16 → 17 | 403 → 405 |
   | Design from saved cohort | 2.42 → 0.89 | 1.43 → 0.10 | 0.070 → 0.061 | 16 → 14 | 401 → 399 |
   | Annual totals | 5.99 → 2.42 | 3.71 → 1.24 | 0.730 → 0.660 | 16 → 16 | 400 → 399 |
   | Cohort export | 5.77 → 2.60 | 3.87 → 1.46 | 0.683 → 0.512 | 10 → 12 | 403 → 401 |

   Values are medians. Execution uses DuckDB's JSON query latency bounded
   by driver elapsed time. Result transfer estimates the extra driver time
   for reads and includes DBI fetch. It excludes SQL rendering and
   collection guard queries' engine time. Keep the separate roster scan and
   the staged second export pass for one minimum-weight placeholder per
   valid hospital-year with zero contributing discharges. Peak memory
   varied little and the measurements support a translation improvement.
5. **Opening, preflight and schema probes (evaluated).** Use a quoted SQL
   projection for one-to-one ASCII column names with either reader.
   Keep dbplyr's lazy projection for Unicode names and coalesces so unused
   coalesces can be dropped before DuckDB binds their types. Keep saved-cohort
   names, source-year validation, and the collection guard.

   Five fresh processes at `7e624f8b` and three after the final change ran
   each reader and release setting on five 500,000-row, 139-column invented
   annual files. Runs used Windows x64, four threads, a 4 GB buffer limit,
   DuckDB 1.5.2, dbplyr 2.5.2, and Arrow 24.0.0. The first query filtered by
   age and counted rows by year. Values are medians in milliseconds. Opening
   render time includes any SQL rendering inside the release check.

   | Reader / release check | Open wall | Open rendering | First query rendering | First DuckDB prepare | Open statements |
   | --- | ---: | ---: | ---: | ---: | ---: |
   | DuckDB / on | 1,220 → 705 | 701 → 2 | 793 → 68 | 8 → 11 | 11 |
   | DuckDB / off | 1,371 → 339 | 935 → 2 | 1,090 → 64 | 11 → 11 | 8 |
   | Arrow / on | 713 → 833 | 1 → 2 | 796 → 50 | 19 → 21 | 12 |
   | Arrow / off | 452 → 442 | 0 → 1 | 875 → 79 | 21 → 25 | 9 |

   Rendering accounted for 57–68% of native open wall time. Arrow already
   deferred that work until the first downstream query. Three alternating
   checked Arrow replays of the prototype showed the same first-render improvement
   (659 → 63 ms). Arrow opening wall time varied, including in the common
   release-check and schema phases before the projection. The measurements
   support faster first-query rendering for Arrow.

   Metadata and schema statements took 51–91 ms at baseline. The five
   physical descriptions establish per-part schemas. The pooled binding,
   which took 13–18 ms, resolves the output schema across heterogeneous files.
   Checked opens issued two different queries against the same key-value
   footers, with no identical SQL repeats. The extra lookup cost 10–12 ms
   including R time. Unchecked opens issued one key-value lookup. The
   checked-release path took 257 ms (native) and 342 ms (Arrow), including
   171 and 235 ms in the projected aggregate. Keep those probes and the
   release aggregate. Their repeated work fell below the 20% threshold,
   and the aggregate checks weights and hospitals that the footers cannot
   establish. The statement counts were unchanged after the port.

   The opening decision completes the port inventory. The retained
   boundaries and owner decisions below still apply.
6. **Keep the remaining boundaries.** Keep R survey materialization for
   `nis_design()` and PSU-only materialization for `nis_survey()`. Keep the
   connection subclass, source attributes
   and finalizers for error translation, guarded dbplyr collection, spill
   cleanup and Arrow lifetime. Keep public `compute()` composable and prefer
   direct Parquet for one-shot internal work. Validate survey GLM
   materialization on multiple iterations and low-cardinality predictors
   before changing it. Leave outcome and disclosure expressions in place
   pending a measured gain. Profile Haven decoding and validation before
   changing any DuckDB SQL in conversion; most of the measured SPSS conversion
   runs outside the engine. Keep R conversion checks and the Parquet-footer publication check
   until a replacement proves identical encoding, row-order and atomicity
   guarantees.

### Slot layout, Parquet and settings comparisons

The controlled PRDAY pipeline prototype used hand-written wide SQL with a
shared DX/PR matcher (`44ea3d01`). Five alternating fresh runs per side used
500,000 invented rows total across five years, 129 columns, 25 PRDAY slots,
16 threads and a 25 GiB DuckDB cap. Median preparation, including upstream
flags, fell from **19.87 s to 4.90 s** (ranges 14.59–23.40 s and 3.59–5.69 s).
Rendering fell from 17.31 s to 3.08 s. DuckDB preparation was 0.09 s on both
sides. Execution and fetch were 14.42 s and 14.23 s, with overlapping ranges.
Peak process commit was 1.486 GiB and 1.483 GiB. Six flags matched by
`(YEAR, ID)` in every run, including independent expectations for missing
days, competing procedures, and exact exclusions. This comparison supports
porting R translation and retaining the wide SQL shape.

<!-- MEASURED PROTOTYPES START -->

The slot-layout experiment timed a single-use aggregate over each proposed
shape. The compared kernels are prefix existence, category-like exact-code
presence, one POA-conditioned comorbidity, and within-three-day timing. The
cores run on the same fixture and return matching counts of total, matched
and indeterminate rows. These are screening measurements; the CCSR-like and
comorbidity kernels cover narrower outputs than the package operations.
Numbers are DuckDB execution and fetch in seconds for 4 / 8 threads.
The raw CSVs also report R construction and preparation.

| Kernel | Wide OR/CASE | List functions | UNPIVOT view | UNPIVOT temp table, subsequent use | Build temp table |
| --- | --- | --- | --- | --- | --- |
| Prefix flag | 1.08 / 0.61 | 3.52 / 1.88 | 4.10 / 2.18 | 1.23 / 1.08 | 6.58 / 3.89 |
| Exact-code category presence | 1.80 / 1.51 | 3.52 / 2.91 | 4.05 / 3.07 | 1.61 / 0.78 | 7.47 / 4.00 |
| POA condition | 3.06 / 1.73 | 10.99 / 5.06 | 5.11 / 2.49 | 1.46 / 0.67 | 9.60 / 4.26 |
| PRDAY timing | 6.21 / 2.76 | 9.22 / 4.87 | 12.58 / 6.49 | 5.49 / 2.57 | 7.35 / 3.79 |

Keep the wide representation for one-shot flag and timing calls. Test the
narrow staged table when repeated operations can amortize the build under
the memory cap. The first timing test with default `UNPIVOT` dropped procedure
codes paired with NULL days and returned 119,330 fewer indeterminate results.
`INCLUDE NULLS` restored those results. The comorbidity layout test alone
does not justify changing the package's scoring joins.

The separate single-category CCSR prototype uses the bundled mapping with
its actual release and category filter. It checks the 40 code slots with
one list intersection. On the fixture both paths count the same category
presence. The prototype took **6.79 / 4.81 s** to execute, with about 15 ms
of prepare time. The baseline repeats 40 joins. This prototype counts
presence for one category in one bundled release and does not implement
multi-category lists.

#### Layers

Times below are inclusive seconds at 4 / 8 threads. Function timers can
overlap the phases in the baseline table.

| Layer | Time | What the measurement supports |
| --- | --- | --- |
| Open, connection setup | 0.16 / 0.32 | One connection per open is part of the resource lifetime. |
| Open, release check | 0.43 / 0.71 | Three statements beyond the skip path. Port 5 separately measures the projected data scan and the repeated footer read. |
| Open, attach finalizer | Under 0.001 / under 0.001 | Keep the ownership hook. |
| Key and eligibility validation before comorbidity scoring | 2.46 / 2.30 | One extra scan and a substantial execution cost. Preserve uniqueness and code-era checks while testing a combined scoring plan. |
| Design tidyselect prototype | 0.16 / 0.19 | Keep type-based selection. Investigate a names-only fast path with equivalent schema validation. |
| R survey design construction | 0.26 / 0.37 | The constructed design retains the rows and the hospital roster required by the R survey workflow. |
| Design collection guard | 0.42 / 0.62 | Two dry planning statements per collect in the measured two collects. Keep the guard for the cohort rows and consider a proven bound for the roster. |
| Timing collection guard | 0.83 / 0.42 | The benchmark collects a scalar. A trusted scalar path can bypass guard queries; a user-constructed query still needs the guard. |
| Cell count collection guard | 0.11 / 0.09 | The cell count can be high cardinality with arbitrary grouping keys. Check known cardinality before bypassing. |
| Convert, R batch validation | 33.66 / 20.45 | Keep validation. Haven's SPSS reader accounts for about 70% / 63% of Rprof samples, making decoding the first place to investigate. |

In five alternating trials the connection subclass ran trivial SQL in
3.4 vs 6.5 ms per statement (plain vs subclass) at 4 threads
and 4.4 vs 8.8 ms at 8 threads. It adds no statements.
For a 1.81 million-row, two-column result the guarded and unguarded paths
took 404 vs 303 ms and 402 vs 339
ms, respectively. A separate forced count took 49 / 49 ms.
The normal guarded runs used estimates and never took that count branch.

#### Parquet layout and settings

Sorting by year and hospital at 122,880 rows per group left one of five
candidate groups for an invented 2% hospital slice. Source order left five
of five. On one annual file, write time was 7.75 → 9.71 s at 4 threads and
7.10 → 7.29 s at 8 threads. Execution changed 52 → 51 ms and 49 → 29 ms,
respectively. At 16,384 rows the pruning improved from 31 candidate groups
to one, with higher metadata and write costs. At 524,288 rows there was
only one group, so sorting could not prune. Casting one diagnosis slot to
ENUM made a difference of under 1 KiB in the sorted files and gave no
clear execution gain. Keep the current Parquet defaults for production
and use recurring real query shapes to decide whether new exports merit
another layout.

Leave `preserve_insertion_order` enabled where conversion preserves source
order. Keep workload settings configurable for thread count and memory.
The narrow repeated scan saw 45 vs 58 ms with metadata caching off vs on
at 4 threads, and 148 vs 93 ms at 8 threads. Order and external-file-cache
toggles also varied on this local workload. The two profiles vary threads
and memory together. These comparisons justify no default changes.
`enable_object_cache` is a legacy no-op in the profiled DuckDB version.
[DuckDB 1.5 configuration](https://www.duckdb.org/docs/1.5/configuration/overview)

<!-- MEASURED PROTOTYPES END -->

## Owner decisions

- **Existing file reconversion.** The footer inspection found Snappy and
  dictionary encoding already in use. Groups are commonly around one million
  rows, with min/max statistics available on hospital, year, and code
  columns. The local receipt records group sizes, encodings and statistic
  availability without exporting key values. Synthetic sorting improved
  pruning in the targeted hospital query and increased write cost. Leave
  existing files in place pending an owner decision about the migration cost
  and the queries that would amortize it.
- **Minimum DuckDB version.** The measurements and instrumentation used 1.5.2.
  Establish the oldest version that can execute the selected production
  builders and pass their correctness and performance gates. The profiling
  API alone does not justify a production minimum.
- **Arrow compatibility.** Arrow is an explicit reader option. Compare the
  native and Arrow rows in the baseline table. Keep the owner decision open
  because reader removal changes malformed-string behavior and available
  recovery paths, and DuckDB cannot govern Arrow allocations with its
  buffer limit.
- **Public table type.** Plain dbplyr behavior currently carries grouping,
  user verbs and backend interoperability. A thinner class would have to
  preserve those contracts and show measurable gains after query rendering
  and redundant probes are addressed. The first ports can keep dbplyr.

## Reproduction

The [experiment scripts](../../tools/experiments/adr-0002) generate and consume
only invented records. Use the DuckDB 1.5.2 environment recorded for this
experiment. The profile readers expect that release's JSON layout. From the
repo root, set `$e` to an existing ignored evidence directory, then run the
following in PowerShell.

```powershell
Rscript --vanilla tools/experiments/adr-0002/capture.R $e fixture 4
& tools/experiments/adr-0002/run.ps1 -Evidence $e
Rscript --vanilla tools/experiments/adr-0002/summarize.R $e
Rscript --vanilla tools/experiments/adr-0002/flamegraph.R $e
Rscript --vanilla tools/experiments/adr-0002/explain.R $e
foreach ($p in 4, 8) {
  foreach ($task in 'flag', 'ccsr', 'comorbidity', 'timing', 'layout', 'settings') {
    Rscript --vanilla tools/experiments/adr-0002/prototypes.R $e $p $task
  }
  Rscript --vanilla tools/experiments/adr-0002/ccsr-presence.R $e $p
  Rscript --vanilla tools/experiments/adr-0002/layers.R $e $p
}
```

Each case retains the DuckDB statement log, JSON operator profiles, Rprof
samples and folded stacks, result or error, per-phase events, and sampled
process memory. Statement counts exclude profiler setup and log export.
DuckDB preparation is measured at the R driver's prepare boundary. Execution
includes native conversion of results to R. The remaining R time includes
the easyNIS wrappers, dbplyr lazy query construction, DBI dispatch outside the
measured boundaries, R materialization after fetching, and instrumentation.
The JSON profiles retain statement-level buffer and spill peaks. Process
commit includes shared allocations and has no additive split by layer.
Parquet/Arrow operator counts indicate scan passes in captured plans, including
pruned or partial passes. A metadata lookup or `DESCRIBE` is a statement but
does not count as a scan operator. A scan count can be incomplete when no JSON
profile was emitted for a statement.

`EXPLAIN ANALYZE` replays the largest eligible read-only statement per case.
Connection-local SQL and writes are represented by profiles from original
execution. The suppression case runs entirely in R. The conversion baseline
uses SPSS; other Haven formats and fixed-width ASCII have different decode paths.

The footer script accepts an explicit licensed directory and writes under
`private/` in the ignored evidence directory. It reads only
`parquet_metadata()` and `parquet_schema()`. The receipt records row-group
sizes, encodings, types, and whether statistics exist. It never projects
record-derived statistic values. Keep the licensed receipt local.
