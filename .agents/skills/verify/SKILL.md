---
name: verify
description: Verify easyNIS through its installed R package and generated Quarto study. Use after changing a user-facing data, cohort, survey, disclosure, or study workflow.
---

# Verify easyNIS

Users work in R with annual Parquet data and may render a generated Quarto
study. Drive the exported functions from a fresh package installation.

## Launch

From the repository root, use R 4.1 or later and install the package
dependencies as described in [Contributing](../../../CONTRIBUTING.md). No
service, credentials, or external data are needed. For a first run, use:

```sh
Rscript --vanilla .agents/skills/verify/drive.R open
```

The driver installs the checkout into a fresh temporary library with
`R CMD INSTALL`, verifies where the loaded namespace came from, and prints
`READY easyNIS` and dependency versions. Each invocation owns its R process,
data, DuckDB connection, and temporary library, so runs can overlap. For the
study, install Quarto on PATH and the optional R packages named in its feature
entry.

## Doctor

```sh
Rscript --vanilla .agents/skills/verify/drive.R doctor
```

`DOCTOR PASS` confirms the checkout is easyNIS and its R version and imported
packages are available. The doctor reads metadata without installing or
running a workflow. For startup failures, inspect the selected run's
`install.txt` and check for `READY easyNIS` in `run.txt`.

## Drive

Use the [feature map](features/README.md) to select the journeys affected by
the change. Run each journey in its own process. The driver checks its
expected user-visible results, prints `RESULT PASS` or `RESULT FAIL`, and
returns a nonzero status on failure. Keep the assertions when a run fails.
For changes to grouped disclosure policy, also run the
[bounded disclosure check](../disclosure-suppression/SKILL.md).

## Evidence

Keep proof under the `EVIDENCE` directory printed for each run. It lives
under the checkout's Git-ignored `local/loop/verification/` directory.
`run.txt` records the command, checkout, installed versions, actions and
results. `input-hashes.txt` records package source hashes and `install.txt`
records installation. The four small-data journeys retain the invented input
as `annual-input.R` and observed output as `results.R`. Study runs retain
the generated analysis source, Quarto config, scaffold listing, render log,
and HTML.

Exercise exported functions with invented inputs and check side effects
alongside returned values. Use the feature expectations to interpret the
artifacts. A normal package check remains part of qualification under
[AGENTS.md](../../../AGENTS.md).

## Cleanup

The driver removes its exact `SCRATCH` directory and prints `CLEANUP PASS`
on normal completion and on R errors. The evidence directory survives.
After a forced interruption, inspect the recorded scratch path and remove it
only after confirming it is that run's generated temporary directory and its
processes have exited. Preserve evidence.

## Helpers

Run `drive.R` through `Rscript --vanilla` as shown in the feature map.
`runner.R` provides isolated installation, evidence capture, and teardown
for the driver and the disclosure check.
