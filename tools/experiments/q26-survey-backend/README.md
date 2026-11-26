# Survey backends on the same Parquet files

This local experiment compares survey's `DBIsvydesign` with the existing
`easyNIS::nis_design()` placeholder design. It installs the current checkout
into an isolated library. It does not modify the package. Run from the repo root
on Windows with PowerShell 7.4 or later and R on PATH. Install the package's
dependencies first. `gtsummary` is used only for the invented-data compatibility
probe.

```powershell
pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile minimum
pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile reference
```

The default input is generated deterministically with seed 26. The fixture has
three annual Parquet files, overlapping hospital IDs across years, invalid
weights, missing ages and stays, and an I50 domain that leaves some hospitals
without discharges. It tests matches in both the first and last diagnosis slots.
The checked-in receipt records the observed fixture results.

For licensed data, set `EASYNIS_DATA` to the local directory containing the
`NIS_2018.parquet`, `NIS_2019.parquet` and `NIS_2020.parquet` directories. Each
must contain four Parquet parts. Only those directories are read.

```powershell
pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile reference -NisRoot $env:EASYNIS_DATA
pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile minimum -NisRoot $env:EASYNIS_DATA
```

For a staged comparison, add `-SplitConstruction` to each command. This
measures each distinct construction once. It then restores the matching
design in a fresh interpreter for each estimator. The DBI design is built by
survey and reconnects to the same view with the same checked settings on
restore. Each placeholder design retains the same cohort and columns as in a
direct run. Staged results give measured peaks for the cold construction
before serialization and for the restored-design estimator including startup
and restore. Their maximum describes the staged workflow. A direct run
measures a single process that builds and estimates. The staged `total_s`
adds construction and estimator time. `load_s` records restore time
separately. The wrapper removes its intermediate designs after the run.

Run the profiles sequentially. Reference uses up to eight DuckDB threads and a
DuckDB memory limit of 60% of physical RAM. Minimum uses four threads and
4,800 decimal MB. Both run on the same Windows host. The 8 GB threshold is
8,000,000,000 bytes of whole-interpreter peak resident memory. The DuckDB limit
controls DuckDB-managed allocations. Windows offers no R heap cap for this run,
so the minimum profile evaluates the threshold after measurement.

## What runs

Both paths read the same Parquet-backed views via DuckDB. Each applies the same
positive, finite design-field rules, scopes stratum and hospital IDs by year,
and uses unscaled `DISCWT` and `nest = TRUE`. The audit verifies annual file
ownership, scoped ID bounds, the binary outcome coding, and the size of the
full sample and domains. Workers check how many rows entered each design and
both models. Means and totals use `na.rm = TRUE`, and models omit missing
observations. For both models, `rescale = FALSE` gives identical weight
scaling through DBI zero-weight domain selection and the smaller placeholder
design, and both use an IRLS tolerance of `1e-10`. Numeric aliases for
`DIED` and `FEMALE` preserve the input coding in `nis_design()` despite its
default factor labels. I50 identifies a prefix in any of `I10_DX1` through
`I10_DX40`. If DuckDB rejects malformed UTF-8 while decoding diagnoses, the
audit records the failure and continues with calls that project numeric fields.
The DBI path uses `subset()` for survey domains and `filter()` for the srvyr
pipeline. The placeholder path passes the relevant cohort and minimal retained
fields to `nis_design()`.

| Call key | Operation |
| --- | --- |
| `mean` | Whole-sample LOS mean |
| `total` | Whole-sample DIED total |
| `by` | Whole-sample LOS mean by year |
| `adult_mean` | LOS mean for female discharges at age 65+ |
| `adult_by` | Same domain by year |
| `hf_mean` | LOS mean for the I50 domain |
| `hf_glm` | I50 domain quasibinomial DIED model with age, sex and year |
| `glm` | Same model on the whole sample |
| `srvyr` | Female age 65+ domain, grouped LOS mean and SE via srvyr |
| `table` | Invented-data-only `gtsummary::tbl_svysummary()` compatibility probe |

Each trial is a new `Rscript` invocation. Construction time includes the
connection and design build. Call time includes any DBI domain selection and
the estimator. The separate process duration includes R startup, package
loading, validation and connection cleanup. The monitor reads Windows' kernel
`PeakWorkingSet64` for the interpreter PID reported by R. The construction
peak includes interpreter startup. The whole-trial peak also includes
validation and teardown. Spill high-water is a lower bound from directory
sampling about every 50 ms. Residual spill bytes are read after the process
exits, before the wrapper removes the trial's spill directory.

The DuckDB config is passed at connection creation on both paths, including
through survey's `...`. Every successful build checks the effective settings on
the connection used. Both retain Parquet insertion order because survey reads
design and analysis variables with separate positional queries. The shared
views use only single-source projections and filters. See
[DuckDB's order preservation rules](https://duckdb.org/docs/current/sql/dialect/order_preservation).

The audit reads the design fields, demographics and outcome before timed
trials. LOS can be cold on its first projection. These are warm-eligible
runs with the OS file cache unmanaged. Paths alternate within
each call. The default is three repeats for successful calls that take less
than 60 seconds end to end (construction plus estimator in direct mode, restore
plus estimator in staged mode). The runner records a single attempt for slower
cases and failures. It records per-run timings and
reports median timings and the largest observed peaks. Comparisons use the
largest symmetric relative difference in point estimates and SEs over all
pairs of successful repetitions. The tolerance is `1e-6`. The srvyr result
also checks against the direct survey result for the same domain.

## Local evidence

Each command prints its ignored output directory under
`local/loop/q26-survey-backend/<UTC timestamp>-<dataset>-<profile>/private/`.
It contains the invocation, hardware, software versions, preflight checks,
effective settings, raw statistics, error logs, `metrics.tsv` and
`summary.tsv`. The database contains view definitions and stays there, along
with the invented Parquet files for fixture runs. Normal completion removes
the isolated library and temporary directories. If the runner is forcibly
interrupted, confirm the worker has exited before removing its owned
temporary directories from that run.

Keep licensed receipts and the database local. Only the checked-in
invented-data receipt can be shared as a raw run artifact.
