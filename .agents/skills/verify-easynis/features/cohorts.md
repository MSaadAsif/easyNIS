# Code-set cohort flags

A researcher declares codes, provenance, applicability, scope and missingness,
then adds a flag while keeping the discharge population intact.

## Sub-features

- Declare a code set through `nis_code_set()`.
- Add a flag through `nis_flag_codes()` without losing discharges.
- Compare collected flags with independently calculated R expectations.
- Reject malformed codes and incompatible scope/applicability.

## How to get to it (user POV)

Use `nis_code_set()` and `nis_flag_codes()` on an imported relation, then
`nis_collect()` to inspect the requested flag. The flag help example is an
additional public entry point covered by R CMD check.

## Driving it with R

Preconditions: the installed smoke workflow supplies entirely invented codes.

- Run `./tools/verify.ps1` and read `installed-workflow.log`. Require key-aligned
  R/SQL agreement and preserved row counts across all six invented year labels.
- Read `package-tests.csv` for exact/prefix matching, normalization, leading
  zeros, slot policies, scopes and missingness cases. Add new boundary cases
  through the exported calls when the contract changes.

## Gotchas

Syntax validity and matching parity do not prove a clinical phenotype or annual
dictionary membership. A new column-selection API needs additional collision
and provenance cases before its own increment can merge.
