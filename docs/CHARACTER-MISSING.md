# Explicit HCUP character missing states

HCUP's [diagnosis notes](https://hcup-us.ahrq.gov/db/vars/i10_dxn/nisnote.jsp)
and [procedure notes](https://hcup-us.ahrq.gov/db/vars/i10_prn/nisnote.jsp) distinguish
blank (missing), lowercase `invl` (invalid) and lowercase `incn` (inconsistent).
These are source quality states, not negative clinical matches. The following
official Core reports explicitly list those categories for I10_DX1 and I10_PR1:

| Year | Public source |
| --- | --- |
| 2017 | [Core summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2017_Core.PDF) |
| 2018 | [Core summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2018_Core.PDF) |
| 2019 | [Core V2 summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2019_Core_V2.PDF) |
| 2020 | [Core V2 summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2020_Core_V2.PDF) |
| 2021 | [Core summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2021_Core.PDF) |
| 2022 | [Core summary](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/MaskedStats_NIS_2022_Core.PDF) |

Generic numeric special-missing formats do not establish these character rules.
Public documentation also does not authenticate a supplied conversion, revision,
case/padding transformation or missing-reason preservation.

## Opt-in experimental matching contract

`nis_flag_codes()` defaults to `special_missing = "reject"`; current malformed
syntax rejection and default provenance remain unchanged. A caller who has
reviewed the source convention can explicitly choose
`special_missing = "hcup_character"` for 2017–2022 inputs.

Only the selected source slots are considered. ASCII trimming precedes exact,
case-sensitive recognition of `invl` and `incn`. This trimming is an implementation
policy, not a claim that HCUP documents tabs or line breaks as additional markers.
Code normalization does not create marker aliases: `INVL`, `Incn`, `.A`, `A`
and arbitrary malformed strings still fail. No source field is overwritten.

Recognized markers are excluded from code matching, including short prefixes
such as `I`. A valid positive match in another selected slot takes precedence.
Otherwise any recognized quality marker makes the flag unknown, even when
`missing = "no_match"` or `"unknown_if_all_missing"` would treat a blank differently.
The existing `missing` argument continues to govern blank/NULL slots. Unrecognized
malformed values reject the entire call, even alongside a valid positive match.
Quarter applicability and explicit/common slot behavior remain unchanged.

Raw values retain the distinct reasons; flag provenance records the marker map,
year scope, recognition policy and unknown-unless-positive rule. Logical unknowns
do not replace source values or turn invalid/inconsistent codes into observed
negatives. Keep source records, aggregate diagnostics and provenance private
until disclosure review.

This conservative flag rule is an experimental package choice, not an analytic
recommendation from HCUP. Saad/Ali's scientific review, clinical set validation,
conversion evidence and annual support gates remain required. The 2017 YEAR
integrity issue is separate and is not repaired by recognizing character markers.

Acceptance includes default refusal, every blank policy, short-prefix safety,
positive/unknown precedence, diagnosis/procedure scopes, exact case/padding,
unrecognized malformed values, raw/source preservation, reason provenance and
independent R/SQL expectations. Installed public calls and full verification,
independent review and protected CI are required before merge.
