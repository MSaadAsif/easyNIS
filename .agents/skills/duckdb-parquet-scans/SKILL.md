---
name: duckdb-parquet-scans
description: Exhaustively check bounded native DuckDB Parquet year planning in easyNIS, and profile a disk-spilling export after changes to scan grouping, year guards, or DuckDB resource settings.
---

# DuckDB Parquet scans

Grouping compatible Parquet parts must preserve the returned rows, year
values, and offending-file diagnostics. A faster scan that accepts a
wrong year can silently corrupt a pooled analysis.

## Check scan semantics

From the repository root with the normal R imports installed, run:

```sh
Rscript --vanilla .agents/skills/duckdb-parquet-scans/check.R
```

The checker installs the checkout, writes real Parquet parts with DuckDB,
and invokes `nis_open_plan_parquet()`, the planner used by `nis_open()`.
It enumerates the Cartesian product of the left and right values in each
same-schema domain in [check.R](check.R), both as annual parts and with
Hive year 2020. The 738 ordered pairs include signed and unsigned integer
bounds, fractional numbers, nulls, floating NaN and infinities, text,
and files without a physical year. Each part contributes one row.

The expected result is declared by the fixture domain. The check compares
accepted row IDs and SQL year values, or the error category and original
offending parts. Hive conflicts precede range diagnostics. The checker
casts the output year to text inside DuckDB so it can distinguish the
minimum signed integer from R's integer missing-value representation.
Expect `EXHAUSTIVE PASS 738`, `RESULT PASS`, and `CLEANUP PASS`.

On failure, read `counterexample.R`, `domains.R`, and `run.txt` at the
printed evidence path. A planner error or row mismatch against the
documented result is a finding. Check the generated physical schema and
DuckDB version before changing the expected result. For a mutation replay,
archive the covered commit in an isolated directory, make the deliberate
change there, and pass that directory as the sole argument to `check.R`.
Two proven mutations are an inclusive annual upper rejection bound in
`nis_open_year_range_predicate()` and always attributing a grouped Hive
failure to the first part in `nis_open_invalid_paths()`.

## Qualify spill throughput and cleanup

```sh
Rscript --vanilla .agents/skills/duckdb-parquet-scans/spill.R
```

Install `jsonlite` in addition to the normal imports and allow about
1.5 GB of temporary space. This check:

- Generates eight million invented rows in four Hive Parquet parts.
- Verifies `nis_open(years = 2020L)` selects the expected files and rows.
- Sorts and writes the whole fixture with a 192 MB DuckDB buffer setting
  and a 768 MB temporary-directory cap.
- Profiles one run per setting, then times five alternating unprofiled
  exports each with one and two DuckDB threads. It checks row count,
  ID bounds, and checksum on every success.
- Forces a spill-cap failure at 1 MB and checks that the output, spill
  directory, and connection are released. Successful runs must release
  them as well.

DuckDB 1.5.2 reported the 1 MB cap through `current_setting()` even when an
export exceeded it. The production connection now applies the cap with
`SET` after opening. The failure test exercises disk enforcement directly.

Record the engine version, median and range, peak buffer bytes, peak spill
bytes, and whether both settings completed. Compare only runs with the
same data, caps, engine, and comparable load. Overlapping timing ranges
warrant a cautious conclusion. Profiles, CSVs, and transcripts survive
under the printed Git-ignored evidence directory. Inputs and output files
are temporary. The timing covers the sorted export. Fixture generation,
connection setup, checksum verification, and profiling runs are outside
that timing.

## Coverage and sync

Package source last checked at `0dfb7f3216b74ba3252c33cc2b39f87f14a071a1`
with R 4.6.1 and DuckDB 1.5.2.

- [Parquet planning, grouping, range checks, and diagnostics](../../../R/open-parquet.R)
- [Public opening and selection](../../../R/open.R)
- [Part discovery](../../../R/open-discovery.R)
- [Connection and spill ownership](../../../R/duckdb.R)

The exhaustive claim applies to the declared two-part native domain.
Arrow, every heterogeneous schema, remote storage, and concurrent failures
need separate coverage. The spill probe measures one blocking sort and
records DuckDB's buffer manager, whose peak differs from process RSS.
Throughput and the best thread setting depend on the workload and machine.
After touching covered code, update the sync commit only after rechecking
the domain, a deliberate failure, and the workload where relevant.
