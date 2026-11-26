# Invented-data receipt

```powershell
pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile minimum -SplitConstruction
```

Recorded on Windows 11 Pro 10.0.26300 with PowerShell 7.6.10, an AMD Ryzen 7
PRO 4750U (8 physical cores, 16 logical processors), 33.64 GB of RAM and a
Samsung NVMe SSD. The profile set four DuckDB threads and a 4,800 MB memory
limit. See `versions.txt` for R and package versions. The script generates
the input from its embedded fixture definition and seed 26.

The nine estimator comparisons and both srvyr-to-survey checks passed at
`1e-6`. The gtsummary compatibility probe succeeded on the placeholder
design. It failed on the DBI design with `missing value where TRUE/FALSE
needed`.

`input-audit.tsv` records the generated inputs. `construction.tsv` and
`metrics.tsv` contain the measured trials. `summary.tsv` and
`srvyr-vs-survey.tsv` contain the comparisons.
