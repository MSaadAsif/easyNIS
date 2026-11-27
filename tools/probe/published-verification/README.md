# Published NIS estimates

[The study list](../reference-studies.yml) gives the exact source locations,
discharge definitions and predetermined tolerances. All three comparisons use
national totals. The corresponding source rows give point estimates without
standard errors. The probe retains its own survey standard errors locally.

Set `EASYNIS_DATA` to the directory containing the annual licensed Parquet
files. In the loop workspace, create
`private/study-verification/references.json` and transcribe the published
totals from the listed source locations. Use the study IDs as JSON keys and
unquoted numbers without thousands separators as values. With the default
workspace this file belongs under the main checkout's ignored `local/loop/`
directory, including when the probe runs from a Git worktree.

Run both commands from a clean repository root.

```sh
Rscript --vanilla tools/probe/published-verification/run.R
Rscript --vanilla tools/probe/readiness.R
```

The probe installs the checkout into an isolated library and writes its
private transcript, diagnostics, and commit-keyed receipt under the loop
workspace. DuckDB uses at most two threads and a 4 GB memory limit. A
comparison fails when the absolute difference divided by the published
value exceeds the predetermined tolerance. Terminal output contains statuses
and coarse relative discrepancies. Keep the transcript, reference values,
receipt and any diagnostics local.
