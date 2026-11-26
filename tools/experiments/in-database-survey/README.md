# In-database Taylor estimation

This experiment tests whether whole-sample National Inpatient Sample estimates
fit within 8 GB of Windows process peak commit. It follows the workload and
fresh-process monitor at `tools/experiments/q26-survey-backend` in local
commit `1d06879`. The prototype lives entirely in this directory.

## What DuckDB computes

- Totals use weighted PSU sums. Means use ratio linearization with the same
  complete-outcome rows in the numerator and denominator.
- The sampled design uses year-scoped hospitals and strata, unscaled
  `DISCWT`, and no finite population correction. The variance includes
  zero contributions for PSUs outside the domain or group or without usable
  outcomes. It centers the PSU sums within each stratum and applies
  `n / (n - 1)` to the centered cross-products.
- Gaussian identity, quasibinomial logit (0/1), and Poisson log models accept
  explicit SQL predictor columns, including year indicators. IRLS returns
  one row of compensated weighted cross-products and deviance per pass.
  The final query computes the variance of complete-case PSU score totals.
  The score uses the final residual with the last working weights, as in
  `survey:::svy.varcoef()`. Covariance is the design sandwich and requires
  no further dispersion multiplier. The residual degrees of freedom are the
  number of complete-case PSUs minus the number of represented strata
  plus one minus model rank, matching `svyglm()`.

The scope is full-rank models on the supplied fixtures and workloads,
first-stage Taylor variance, and survey's default failure rule for a
sampled singleton in an active stratum. The SQL interface assumes trusted
expressions and small numeric groups. The normal equations use diagonal
scaling and Cholesky. Rank-deficient fits, step halving, alternate lonely
PSU policies, other link functions, and the R formula interface are outside
the experiment.

## Invented data

From the repository root, with R, DBI, duckdb, survey, srvyr and dplyr:

```powershell
$out = 'local/loop/in-database-survey/invented'
New-Item -ItemType Directory -Force $out
Rscript --vanilla tools/experiments/in-database-survey/verify.R $out
```

`verify.R` generates each input deterministically and writes and reads
annual Parquet files. The checked-in [receipt](fixture/manifest.txt) records
the seeds, platform, dependencies and outcome. The
[comparison](fixture/agreement.tsv) records each case's relative
differences and pass/fail. The cases vary PSU and stratum sizes, include a
two-PSU stratum with no domain members and PSUs with no usable outcomes, reuse
hospital identifiers across years, and exercise both values of `na.rm`.
The model checks include the entire covariance matrix, residual degrees of
freedom and IRLS iteration count.

## Licensed data

On Windows with PowerShell 7.4 or newer, install `jsonlite` in addition to
the fixture dependencies. Set `EASYNIS_DATA` to a directory with four
Parquet parts in each of `NIS_2018.parquet` through `NIS_2022.parquet`.
Run from the repository root:

```powershell
pwsh -NoProfile -File tools/experiments/in-database-survey/run.ps1 -NisRoot $env:EASYNIS_DATA
```

The runner compares 2018–2020 and 2018–2022, using four threads and 4,800 MB
in the minimum profile and eight threads and 60% of physical RAM in the
reference profile. Each measurement uses a new Rscript and builds its own
views or in-memory survey design in that process. The timing table uses the
median end-to-end time, including interpreter startup. A separate column in
the local summary isolates time inside the analysis. Three repeats run for a
cell whose first trial finishes in less than a minute. Scale and profile
order reverse on alternate repeats. The design-only audit and earlier
workloads can warm the OS cache. The runner leaves the OS cache unmanaged.

Windows reports process peak working set and peak commit
(`PeakWorkingSet64` and `PeakPagedMemorySize64`). The 8 GB threshold is
8,000,000,000 bytes and applies to process peak commit. The DuckDB query
profiler and a directory sampler record temporary-file high-water marks.
The runner checks for residual files after each process exits.

| Call | Estimator |
| --- | --- |
| `mean` | Mean LOS |
| `total` | DIED total |
| `by` | Mean LOS by year |
| `adult_mean` | Mean LOS for females aged 65+ |
| `adult_by`, `srvyr` | That domain's mean LOS by year, compared with survey and srvyr respectively |
| `glm` | Quasibinomial DIED model with age, sex and year |
| `adult_glm` | That model for ages 65+ |
| `gaussian`, `poisson` | LOS model with age, sex and year |

The three-year SQL trials compare individually with the corresponding
in-memory reference. Agreement is the maximum symmetric relative difference,
using `max(abs(a), abs(b))` as the denominator for nonzero values and a
tolerance of `1e-6`. The licensed Parquet query projects numeric fields.
The age-only fit replaces the Q26 diagnosis-domain fit because the source
diagnosis columns contain malformed UTF-8 and a sex coefficient needs
variation in sex. The Q26 table-formatting call is outside the estimator
experiment.

The runner prints an ignored local evidence directory. Its environment
manifest includes settings and harness hashes. The audit RDS files retain
excluded-row counts by field, and `metrics.tsv`, `summary.tsv`, and
`agreement.tsv` describe the trials. Per-trial raw values, logs and query
profiles stay in the same ignored directory. The checked-in receipt uses
invented inputs only.
