# Import and validation

A researcher opens a session, imports parquet and inspects structural issues
without treating the result as validated annual analysis.

## Sub-features

- Import invented 2017–2022 fixtures without changing their files.
- Collect an explicit projection and retain row counts.
- Select columns lazily while retaining imported schema and derived definitions.
- Distinguish selected-out fields, unverified absence and aggregate SQL NULLs.
- Reject flag names that reuse omitted source columns or flag definitions.
- Report structural validity and experimental analysis status separately.
- Close the session and remove invented files after success or errors.

## How to get to it (user POV)

Call `nis_open()`, `nis_import()`, `nis_select()`, `nis_collect()`, `nis_validate()` and
`nis_close()` from the installed R package. The installed help example for
`nis_import` is another entry point exercised by source-package checks.

## Driving it with R

Preconditions: run the doctor; the full verification command installs the source.

- Run `./tools/verify.ps1`. Inspect `installed-workflow.log` for successful
  invented-year imports, selections, validations and omitted-source-name
  rejection for every label 2017 through 2022.
- Inspect `package-tests.csv` and `check.log` for join, schema, key precision,
  failure cleanup and offline help-example checks.
- For a bug, add a public-call regression case with invented data that fails
  before the fix and passes afterwards. Preserve the before/after evidence.

## Gotchas

Structural checks do not authenticate official layouts, conversion histories or
missing-reason meanings. Licensed files are never part of this verification map.
