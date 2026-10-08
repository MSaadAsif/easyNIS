# Experimental code matching

`nis_code_set()` and `nis_flag_codes()` implement matching on raw `I10_DX1`,
`I10_DX2`, and subsequent diagnosis slots, or `I10_PR1` and subsequent procedure
slots. They do not certify annual layouts, clinical code sets, or analysis
readiness. No clinical code sets are bundled. The capability roadmap remains
at target status for every year.

## Declare the set

Provide character codes, coding system, explicit valid years, version, source,
and author. Numeric code vectors are refused because leading zeros are part
of procedure codes. Exact matching tests complete strings. Prefix matching
tests literal beginnings, without regular expressions or SQL wildcards.

Normalization is off by default. Turn it on explicitly to trim ASCII spaces,
tabs, carriage returns and line feeds, uppercase, and remove diagnosis decimal
points on both sides of the match. Malformed set and observed decimals are
refused before normalization. Procedure decimal points are always invalid. Raw source columns
remain unchanged. Syntax does not establish dictionary membership, complete
billable codes, clinical sensitivity, or specificity.

Diagnosis syntax permits 3 to 7 compact characters for exact matching and a
decimal after the third character. Procedure syntax requires seven characters
for exact matching and excludes I and O. Prefixes can be shorter. These are
syntax guards based on [CDC's diagnosis-code description](https://www.cdc.gov/nchs/data/nhsr/nhsr089.pdf)
and the [CMS procedure reference manual](https://www.cms.gov/medicare/coding/icd10/downloads/pcs_refman.pdf),
not audited annual dictionaries.

The declared years and quarters apply to every code in a set. Build separate
sets when their applicability differs. These are discharge-calendar periods,
not an automatic translation of fiscal-year code releases. An undeclared data
year fails. A quarter-restricted set requires valid DQTR values for every row,
and records outside those quarters receive NA even when their string matches.

## Choose the flag policy

Every call requires a scope and missingness policy. A positive match takes
precedence over null or blank selected slots within the applicable period.
Nonmissing selected source codes must have complete system-compatible syntax.
Malformed values stop matching with aggregate diagnostics rather than produce
negative flags. Blank slots use the same ASCII whitespace rule as normalization.

| Missingness policy | When no selected slot matches |
|---|---|
| `no_match` | Return FALSE, including rows whose selected slots are all missing. |
| `unknown_if_all_missing` | Return NA when every selected slot is null or blank; otherwise FALSE. |
| `unknown_if_any_missing` | Return NA when any selected slot is null or blank; otherwise FALSE. |

Principal diagnosis uses slot 1. Secondary diagnosis uses slots above 1.
All diagnosis and procedure scopes use their respective available slots.
An explicit `slots` argument must contain unique, present, positive numbers
allowed by the scope. The same numbers across years define a common-slot
sensitivity analysis. The default uses observed available columns and records
that choice, without certifying that the conversion includes all source slots.

Flags are logical columns on a new lazy relation. Existing fields cannot be
overwritten, including case-insensitive name collisions with imported fields
or recorded flag definitions omitted by `nis_select()`. Every discharge is
retained. The original relation and raw codes remain available. Provenance
records the original code set, matching policy, scope, missingness policy, and
exact selected columns. A flag is a candidate domain indicator; it does not
approve survey inference or clinical interpretation.

## Evidence and remaining gates

Invented tests compare the SQL matcher with an independent R calculation for
exact and prefix matching under all three missingness policies. They cover
principal/secondary differences, normalization, leading-zero procedure codes,
quarter restrictions, quoted names, and a match present only in a later slot.
Using two common slots gives identical flags across the two invented year
layouts; using all observed slots exposes their difference.

NIS-006, NIS-010, and the clinical review portions of NIS-011 remain pending.
These tests do not promote annual cohort support. Conversion aliases, source
missing reasons, annual code changes, and user phenotypes still require review.
