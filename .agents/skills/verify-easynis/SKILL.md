---
name: verify-easynis
description: Verify easyNIS R package increments through source checks and installed public workflows using invented parquet inputs. Use before committing or when reproducing an import, validation, cohort, or capability regression.
---

# Verify easyNIS

## Launch

From the repository, run `./tools/verify.ps1 -Doctor` followed by
`./tools/verify.ps1` in PowerShell. On other systems use
`Rscript tools/verify.R --doctor` then `Rscript tools/verify.R`.
This is a library, so no server is launched. The full command builds and installs
the source package into a unique ignored library, then starts a separate R
process that loads that installed package.

## Doctor

The doctor is read-only. Require the DESCRIPTION-pinned roxygen2 and DBI,
DuckDB, testthat, pkgload, Arrow and survey before driving. The PowerShell wrapper also
checks Git and GitHub authentication. Use the ignored local configuration or
`EASYNIS_RSCRIPT` and `R_LIBS_USER` to select machine-specific runtime paths.

## Drive

Read `features/README.md` and the matching recipe. The baseline installed
workflow is `tools/smoke-installed.R`, called automatically by verification.
For a new feature add a real exported-interface path and an independent
expected result; then update its recipe. Existing package tests cover joins,
resource cleanup, schema failures and code-set edge cases, and the separate
offline tool suite covers annual-layout parsing. Use only invented records.

## Evidence

The full command reports a unique `.audit/verify/` directory containing source
fingerprints, HEAD and worktree state, package versions, test results, build,
tarball, installation, source-check and installed-workflow logs. `summary.txt`
exists only after every gate succeeds. Read actual logs, not just the verdict.
Working-tree changes after verification invalidate affected evidence; the head
file identifies the baseline and does not imply dirty source was committed.
The merge gate separately requires CI and independent review of the committed
head. Test counts do not promote year support.

## Cleanup

The installed smoke script closes the DuckDB sessions it opens and deletes its
invented temporary parquet files, including on failure. The command exits its
own R processes; it does not kill processes by name. Build and installed-library
artifacts stay in the ignored evidence directory for inspection. Preserve all
logs; remove an entire old evidence directory only when explicitly cleaning
local artifacts and after checking its resolved path.

## Helpers

`tools/verify.ps1` selects the local runtime. `tools/verify.R` runs package gates.
`tools/smoke-installed.R <isolated-library>` drives the installed public API.
`tools/merge-verified.ps1` checks a reviewed PR; its default does not merge.
