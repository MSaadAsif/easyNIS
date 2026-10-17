# Experimental ICD-9 support

## Evidence level

The coding transition is described in the HCUP NIS introductions linked below:
2015 Q1-Q3 discharges use ICD-9-CM and Q4 uses ICD-10-CM/PCS; earlier annual
files use ICD-9-CM. The implementation's field-layout assumptions remain
unverified against official layout files or real NIS data:

- Pre-2015 files use `DX1`-`DX25` and `PR1`-`PR15`; the 2015 Q1-Q3 files may
  use up to `DX30`. Slot discovery therefore uses numeric suffixes, not fixed
  maxima.
- 2015 Q1-Q3 and Q4 diagnosis/procedure data are distributed as separate
  files linked to Core by `KEY_NIS`, with `DX*`/`PR*` for ICD-9 and
  `I10_DX*`/`I10_PR*` for ICD-10.
- `DXVER` and `PRVER` values and their suitability for selecting a coding
  system relative to `DQTR` have not been validated for this implementation.

Check these details against the current HCUP documentation before relying on
the feature for real files.

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
