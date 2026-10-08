# Experimental survey design and domains

The installed public workflow constructs a complete invented-year design and
then subsets logical domains. It checks an independently calculated weighted
total and variance with hospitals absent from the domain.

Run `./tools/verify.ps1 -Doctor`, which requires the optional survey package for
development verification, then `./tools/verify.ps1`. The installed workflow
exercises `nis_survey_design()` and `nis_domain()` for every invented 2017-2022
label. Inspect `installed-workflow.log`, package test results and source check.
Offline help examples construct a native design and domain.

The package suite compares direct native reference designs and independent
arithmetic, including domain mean linearization, missing outcomes, singleton
rejection, raw/exact identifiers, BIGINT weights, unsafe probabilities, logical
missingness and nondefault option preservation. It does not certify annual
conversions or promote scientific approval. Read `docs/SURVEY.md` for the
method contract, inference limits and unbenchmarked eager-memory behavior.

The installed workflow also pools all six complete invented-year designs after
their DuckDB sessions close. It verifies 24 separate year/hospital PSUs and
12 year/strata, plus independently calculated combined and average annual
domain totals and variances. The package suite adds direct native references
with reused identifiers and varying annual weights, and rejects duplicate years,
prior domains and incompatible fields/levels. Read `docs/POOLING.md` for the
explicit estimand/divisor contract and remaining scientific gates.
