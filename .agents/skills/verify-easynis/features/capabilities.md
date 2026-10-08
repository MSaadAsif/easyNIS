# Capability lookup

A researcher checks which years have validated support instead of assuming an
importable year is ready for statistical analysis.

## Sub-features

- Query target years with `nis_supported_years()`.
- Request release-supported years with `supported_only = TRUE`.
- Keep scientific claims tied to the installed support matrix and evidence.

## How to get to it (user POV)

Call `nis_supported_years()` or run its installed help example. The installed
CSV matrix is the authoritative capability source.

## Driving it with R

Preconditions: this development baseline has no release-supported year.

- Run `./tools/verify.ps1`. The installed workflow asserts an empty
  `nis_supported_years(supported_only = TRUE)` result.
- Read `package-tests.csv` for year queries and matrix consistency checks.
- When scientific approval permits a capability promotion, deliberately update
  the smoke expectation, this recipe and the approval evidence together.

## Gotchas

Do not change the support matrix merely to satisfy a failed assertion. A merge
and a passing structural test are not scientific approval.
