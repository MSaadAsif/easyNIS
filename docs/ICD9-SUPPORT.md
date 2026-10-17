# Experimental ICD-9 support

## Evidence level

Verified (read directly during development, October 17, 2026):

- The local NIS 2020 Introduction states that discharges in 2015 Q1-Q3 are
  coded in ICD-9-CM and Q4 in ICD-10-CM/PCS, and that earlier annual files
  are ICD-9-CM only.

Assumed (secondhand: search-engine excerpts of HCUP layout documents; the
HCUP pages could not be fetched directly in this environment, so none of the
following has been checked against a primary file or document):

- Pre-2015 files use `DX1`-`DX25` and `PR1`-`PR15`; the 2015 Q1-Q3 files may
  use up to `DX30`. Slot discovery therefore uses numeric suffixes, not fixed
  maxima.
- 2015 Q1-Q3 and Q4 diagnosis/procedure data are distributed as separate
  files linked to Core by `KEY_NIS`, with `DX*`/`PR*` for ICD-9 and
  `I10_DX*`/`I10_PR*` for ICD-10.
- `DXVER` and `PRVER` take the values 9 and 10 for the ICD-9 and ICD-10
  systems, and HCUP recommends `DXVER` over `DQTR` for the 2015 split because
  discharge quarter can be missing.

Re-check these against the HCUP documentation before relying on the feature
for real files.

Pointers (public documentation, not patient records):

- <https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2012.jsp>
- <https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2015.jsp>
- <https://hcup-us.ahrq.gov/db/vars/dxver/nisnote.jsp>
- <https://hcup-us.ahrq.gov/db/vars/prver/nisnote.jsp>

## Implementation contract, not verified facts about an analyst's files

`nis_open()` reads already prepared annual Parquet files; it neither imports
HCUP distributions nor validates their joins. Analysts must retain all Core
discharges when joining the split 2015 files, preserve official slot names,
store codes as upper-case strings without decimal points, and leave slots
of the other system missing. This input contract has been tested only with
invented public fixtures, not with licensed NIS records.

The existing flag API gains `system = c("icd10", "icd9")`. This reuses the
same prefix, position, malformed-UTF-8-safe matching, and lazy Arrow kernels
without additional exports or a second implementation. It never searches
the other namespace. Available non-missing `DXVER`/`PRVER`, `YEAR`, and
2015 `DQTR` must agree with the requested system. Contradictory/invalid
metadata suppresses a match rather than guessing which field is correct.
Missing metadata relies on the namespace; quarter alone without `YEAR`
cannot establish an era. This is not a comprehensive file-validation tool.

## Analyst decisions and limitations

- Apply separately justified code sets for each era and explicitly combine
  the two logical flags. There are no clinical lists, mappings, or claims
  of equivalence. A false flag is not evidence that a condition is absent.
- Treat October 2015 as a discontinuity even with both definitions; assess
  code-set changes, slot counts, and derived-variable availability before
  interpreting trends. External-cause fields are not diagnosis-slot inputs.
- Common existing labels are reused; unknown codes are still retained and
  warned about. Historical ICD-9-specific indicators do not acquire the
  labels/definitions of similarly named ICD-10 fields.
- Existing CPI-U values support all 2012–2015 years without changes to the
  cost formula. Correct annual `CCR_NIS` inputs remain the analyst's job.
- `nis_example()` retains its 2017–2022 default. Optional 2012–2015 data
  use invented strings for testing, not validated medical code sets or a
  crosswalk. The fixture is NIS-shaped, not a complete historical schema.
