# Open annual Parquet

## Sub-features

Open annual files alongside Hive parts, select a year, aggregate a lazy
query, and release it.

## How to get to it (user POV)

Call `nis_open(path, years = ...)` in R and use dplyr verbs before
`collect()`.

## Driving it with Rscript

```sh
Rscript --vanilla .agents/skills/verify/drive.R open
```

Open an annual 2019 file and a Hive 2020 part with no physical year field.
Expect a lazy query, four discharges per year, and a 2020-only key sum of 26.
Observe the private DuckDB spill directory while the query is live and its
removal after releasing it. Inspect `results.R`.

## Gotchas

DuckDB's query order is unspecified without an explicit sort. The small
fixture observes the lifecycle of the spill directory. It does not force a
disk spill or measure throughput.
