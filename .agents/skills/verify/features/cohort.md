# Define a cohort

## Sub-features

Flag principal and any-position diagnoses, flag procedures, evaluate timing
with unknown days, and count sequential attrition.

## How to get to it (user POV)

Pipe an open query through `nis_flag_dx()`, `nis_flag_pr()`, or
`nis_flag_pr_timing()`. Pass the resulting criteria to `nis_attrition()`.

## Driving it with Rscript

```sh
Rscript --vanilla .agents/skills/verify/drive.R cohort
```

Each year repeats four invented patterns. The second discharge matches the
diagnosis only in a secondary slot and has an unknown outcome day. The
first outcome follows the index, the third precedes it, and the fourth is
absent. Expect attrition to retain eight, then six, then two discharges.
Inspect the ordered flags and counts in `results.R`.

## Gotchas

The fixture uses ICD-10 slots. Indeterminate timing is `NA` and an
indeterminate criterion drops the discharge from the next attrition step.
