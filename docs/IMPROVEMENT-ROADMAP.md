# Path to 1.0

The improvement loop in [LOOP.md](LOOP.md) turns real workflow friction and
package checks into reviewed fixes. `tools/probe/readiness.R` reports the
current status of each criterion below; evidence stays local when it contains
real NIS results.

## Ready criteria

1. **R CMD check --as-cran:** zero errors, warnings, and notes on CI. See the
   `R CMD check --as-cran` criterion in `readiness.R`. CI runs are looked up
   by the current commit SHA; readiness still requires an `R-CMD-check` run
   with that exact head SHA, completed status, and successful conclusion.
2. **rOpenSci packaging guide:** conform to the packaging guide. See
   `rOpenSci packaging-guide conformance`.
3. **Coverage:** test coverage is at least 90%. See `Test coverage >= 90%`.
4. **Examples:** every exported function has runnable examples. See
   `Every export has runnable examples`.
5. **Workflow documentation:** pkgdown documents the full analyst workflow.
   See `pkgdown documents the full workflow`.
6. **Complexity:** cyclomatic complexity is at most 15 for every function.
   CI and the quality probe measure the installed namespace with `cyclocomp`.
   The readiness report requires a passing receipt for the current commit.
7. **Published-study verification:** reproduce headline estimates from three
   published NIS studies within a stated tolerance. Run verification locally
   against licensed data using the [published-estimate probe](../tools/probe/published-verification/README.md).
   The readiness criterion shows pass/fail and coarse relative discrepancies.
   Keep estimates, standard errors, and receipts local.
8. **Issue severity:** no open P0 or P1 issues. See `No open P0/P1 issues`.
9. **Performance.** Every workload step meets the
   [performance budgets](#performance-budgets) under both profile settings.
   Each repeat must meet all three limits and leave zero temporary files.

## Performance budgets

The minimum Windows profile has 8 GB RAM, 4 cores, and 20 GB free disk.
The reference Windows profile has 16 GB RAM, 8 cores, and 20 GB free disk.
The probe sets DuckDB to 4 GiB and 4 threads for minimum, and 8 GiB and
8 threads for reference. Both use a 16 GB DuckDB spill cap. The settings
simulate the profiles on a shared host. The probe samples the process commit
ceiling and leaves host RAM, CPU scheduling and the OS file cache unmanaged.

With the package's development dependencies and `gtsummary` installed, run
the probe and readiness report from the repository root.

```sh
Rscript --vanilla tools/probe/probe-performance.R
Rscript --vanilla tools/probe/readiness.R
```

The probe installs easyNIS into an isolated library and generates six annual
Parquet files of seven million invented discharges each (2017–2022). Each file
has 120 columns, including 40 diagnosis and 25 procedure slots. The typical
cohort uses five years (2018–2022) and matches about 1% of discharges on an
I50 diagnosis in any slot. The invented cohort is concentrated in a subset
of hospitals and exercises the survey design's hospital placeholders.
The cohort-building step forces a SQL scan with a count. The design step
retains age, sex, mortality and length of stay.
The weighted descriptive step estimates mean length of stay overall and by
sex. The mortality model uses age, sex and year. The summary table reports
age, length of stay and mortality by sex. Both open steps use the default
annual release checks.

Each step runs three times per profile in a fresh R interpreter. Wall time
measures the named operation. For downstream steps, opening, flagging and
constructing the required design happen before timing starts. The six-year
whole-sample step times design construction and fitting together. Windows
process peak commit (`PeakPagedMemorySize64`) includes startup and prerequisites.
Temporary disk is the largest observed total file size in the dedicated
scratch directory, sampled about every 50 ms. The process exit check counts
any leftover files before the probe removes scratch. Sampling can miss
short-lived files. Each run records individual repeats, medians and maxima
under the Git-ignored `local/loop/` directory.

Use `--smoke` for one small invented run per step and profile. For optional
licensed validation, set `EASYNIS_DATA` to a local NIS Parquet root containing
2017–2022 and run with `--real`. The probe reads that root and keeps only
resource measurements and run status. Readiness uses the full invented run
for the current clean commit.

### Limits

Each cell lists peak commit in decimal MB, wall time in seconds, and temporary
disk in decimal MB. Each repeat must also leave zero temporary files.
The runner reads the same limits from
[`performance-budgets.tsv`](../tools/probe/performance-budgets.tsv).

| Step | Minimum (MB / s / MB) | Reference (MB / s / MB) |
| --- | ---: | ---: |
| `nis_open()`, 1 year | 300 / 7 / 1 | 300 / 7 / 1 |
| `nis_open()`, 5 years | 300 / 14 / 1 | 350 / 10 / 1 |
| Build the cohort | 500 / 60 / 1 | 600 / 30 / 1 |
| `nis_design()`, cohort | 750 / 121 / 1 | 750 / 79 / 1 |
| `svymean()` and `svyby()`, cohort | 850 / 13 / 1 | 850 / 14 / 1 |
| `svyglm()`, cohort | 1000 / 14 / 1 | 1000 / 13 / 1 |
| `tbl_svysummary()`, cohort | 1000 / 88 / 1 | 1000 / 80 / 1 |
| `nis_survey()` and `svyglm()`, whole sample, 6 years | 8000 / 166 / 1 | 650 / 166 / 1 |

The core limits use the largest observed value plus 25%, rounded up to the
next 50 MB of commit, whole second, or whole MB of disk, with a 1 MB disk
floor. The shared Windows calibration host had 33.6 GB RAM and 16 logical
cores. Other jobs were active during the run, and some repeats overlapped.
Each profile completed three repeats of each core step. Below, commit and wall
time are median / maximum. Temporary disk was 0 / 0 MB for every core step at
both profiles, and every repeat left zero temporary files.

| Step | Min. commit (MB) | Min. wall (s) | Ref. commit (MB) | Ref. wall (s) |
| --- | ---: | ---: | ---: | ---: |
| Open 1 year | 206.8 / 206.9 | 4.29 / 4.81 | 231.1 / 233.1 | 4.33 / 5.19 |
| Open 5 years | 223.6 / 223.7 | 9.40 / 10.49 | 256.1 / 257.3 | 6.87 / 7.57 |
| Cohort | 374.8 / 378.2 | 43.74 / 47.39 | 443.4 / 445.5 | 23.30 / 23.38 |
| Design | 571.9 / 572.6 | 94.22 / 96.52 | 561.3 / 562.6 | 54.36 / 62.45 |
| Weighted means | 664.3 / 676.7 | 9.29 / 9.89 | 667.9 / 672.2 | 9.25 / 10.48 |
| Model | 792.4 / 793.9 | 10.42 / 10.46 | 788.8 / 790.0 | 9.32 / 10.25 |
| Summary table | 779.8 / 783.1 | 63.39 / 69.84 | 774.5 / 774.9 | 59.68 / 63.67 |

The original in-memory six-year whole-sample workflow crossed 8 GB peak
commit. The calibration stopped the minimum-profile trial at 8004 MB after
132.34 seconds of process time. The reference trials stopped at the host
commit headroom check. The provisional wall and disk limits use the stopped
trial with the same margin and rounding as the core limits.

The whole-sample step uses the
[in-database estimator](adr/0001-in-database-survey-estimation.md).
Run `Rscript --vanilla tools/probe/probe-performance.R --whole-sample` to
measure this step on both profiles. On the 42-million-row invented fixture,
grouping repeated model rows reduced the number of full Parquet scans
during IRLS from seven to two, including the grouping pass. Each row below
reports the maximum commit and wall time across three fresh processes per
profile on the shared Windows host.

| Data | Minimum (MB / s) | Reference (MB / s) |
| --- | ---: | ---: |
| Invented, before grouping | 391.8 / 319.01 | 452.7 / 123.97 |
| Invented, with grouping | 390.6 / 147.86 | 448.9 / 64.79 |
| Licensed, historical pre-grouping run | 437.6 / 278.79 | 511.3 / 160.86 |

All repeats used zero temporary disk and left zero temporary files. Both
invented profiles with grouping met the existing limits for the whole-sample
step. The full probe is needed to qualify all of criterion 9.

## Scope decisions

- Defer the synthetic template study (Phase D/R8). The completed HOCM
  myectomy-versus-ablation study remains a reference, not new work.
- easyNIS implements named comorbidity definitions in DuckDB. Use published
  mappings and weights supplied by an upstream package when available.
  Distribute a versioned reference table with provenance and licensing when
  that package does not supply the definition.
- HOCM backlog item #3 (curated cardiac device code sets) remains deferred.
- Bundle the official AHRQ HCUP CCSR diagnosis and procedure mappings and
  refresh them with AHRQ's annual releases.
- Keep easyNIS focused on a simple NIS analyst workflow built on established
  packages including `survey`, `srvyr`, `gtsummary`,
  `medicalcoder` and `duckdb`.
- Use [in-database Taylor linearization](adr/0001-in-database-survey-estimation.md)
  for whole-sample and large-domain totals, means, grouped estimates, and
  canonical-link GLMs. Keep cohort-scale and row-level methods on
  `nis_design()` with `survey`, `srvyr`, and `gtsummary`.

## Completed history

The literature challenge set reviewed 12 original NIS studies and established
the existing survey workflow as the core product direction. The HOCM study is
complete. Repository comparison tests for `nis_design()` use invented data;
they are not independent external validation.
The archived research report is `docs/research/2026-10-nis-literature-report.md`.

## Report corrections

The archived report's claim that no `nis_design()` validation artifact exists
is corrected above: repository comparison tests exist, but independent external
validation remains a Path to 1.0 criterion.

## Out of scope

- Broad pre-2012 support, including `TRENDWT`, before annual layouts are verified.
- Person-level linkage, longitudinal or readmission helpers, and state estimates.
- Post-2011 hospital volume inferred from sampled discharge counts.
- Wrappers for general statistical methods already supported by established R
  packages, or preflight tools that choose scientific assumptions for analysts.
