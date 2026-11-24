# Build a survey design

## Sub-features

Define the cohort within the survey design, annualize discharge weights,
adjust costs, and multiply the weights by supplied factors.

## How to get to it (user POV)

Pass the flagged query and a cohort expression to `nis_design()`.
Summarize it with srvyr and pass aligned numeric factors to `nis_reweight()`.
Read cost adjustment details with `nis_cost_provenance()`.

## Driving it with Rscript

```sh
Rscript --vanilla .agents/skills/verify/drive.R survey
```

Select principal diagnoses in both fixture years. The four retained weights
sum to 20 before annualizing and 10 afterward. A factor of two doubles the
annualized total and its standard error. The 2020 discharges have cost 250
in 2020 dollars. Inspect survey totals and cost provenance in `results.R`.

## Gotchas

Keep the full sample available to `nis_design()` so it can account for
hospital-years with no cohort discharges. The reweighted total checks the
weight transformation and has no national interpretation.
