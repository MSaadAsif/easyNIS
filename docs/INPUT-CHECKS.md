# Check converted inputs before analysis

Install the development package using the [README](../README.md), then run this
offline walkthrough in R. It creates only invented temporary Parquet files,
closes its session and removes those files on success or error. It writes no report.

```r
checks <- source(system.file("examples/input-checks.R", package = "easyNIS"))$value
checks
```

| Invented case | Import | Structural errors | Analysis ready | Next step |
| --- | --- | --- | --- | --- |
| Canonical fields | Accepted | FALSE | FALSE | Review annual metadata and conversion evidence. |
| HOSPID/TRENDWT in place of HOSP_NIS/DISCWT | Accepted | TRUE | FALSE | Authenticate field meanings and conversion profile before any explicit mapping. |
| One YEAR differs from the declared year | Rejected | No report | No report | Resolve source integrity with documented evidence; do not relabel or drop rows. |

Import success means a lazy relation was constructed. Run `nis_validate()` before
analysis: a Core-only import can succeed while required design fields are absent.
`analysis_ready` remains FALSE even when structural checks pass and provenance
is supplied. Names, row-count agreement and caller declarations do not validate
annual methods or conversion history. See [SUPPORT.md](SUPPORT.md).

For your own local files, use the existing interfaces inside a function so cleanup
runs on errors too. Replace the path and year with your authenticated inputs.
This code performs local structural queries; it does not approve the input.

```r
inspect_input <- function(core_path, year, conversion_notes = list()) {
  session <- nis_open()
  on.exit(nis_close(session), add = TRUE)
  imported <- nis_import(session, core_path, year, provenance = conversion_notes)
  nis_validate(imported, fields = c("YEAR", "KEY_NIS", "HOSP_NIS",
    "NIS_STRATUM", "DISCWT", "AGE", "LOS", "I10_DX1"))
}
# report <- inspect_input("local-core.parquet", 2022)
# report$issues
# report$fields
# report$components
```

An import rejection can be inspected locally with `tryCatch(...,
nis_structure_error = identity)`: `check`, `component`, `fields` and `affected`
describe the structural failure without returning discharge identifiers or row
values. Other errors still propagate. A rejected import has no validation report;
do not substitute a successful status or continue analysis.

The expected structural names are YEAR, KEY_NIS, HOSP_NIS, NIS_STRATUM and DISCWT.
Numeric code columns can lose leading zeros. Legacy aliases require evidence of
the original identifier or weight meaning, year and transformation; easyNIS
does not infer that HOSPID or TRENDWT is an appropriate replacement. In
particular, a filename year cannot repair mixed or invalid YEAR values.

A code-syntax rejection can also reflect documented lowercase HCUP character
quality markers. Review [CHARACTER-MISSING.md](CHARACTER-MISSING.md) before
explicitly opting in with `special_missing = "hcup_character"` when flagging.
This preserves invalid/inconsistent reasons and unknowns; it does not repair
arbitrary malformed codes, authenticate a conversion or resolve YEAR integrity.

`fields` distinguishes `present`, `user_omitted` after `nis_select()`, and
`unverified_absent`. Absent-field NULL counts are unknown, not zero. For present
fields, `record_nulls` counts SQL NULLs only; it does not decode special missing
sentinels, recover labels or establish clinical meaning. Inspect full input
before narrowing fields and retain the fields required for your later analysis.

Supply separate components through `hospital`, `severity` and
`diagnosis_procedure_groups` only when their origin and joins are known. Hospital
joins use YEAR/HOSP_NIS; other joins use YEAR/KEY_NIS. Required keys must be unique,
every Core row must match, and shared non-key values must agree. A component
reported `not_supplied` is not proven unavailable in the official source. Merged
column names do not establish that component provenance has been preserved.

Record known `conversion`, `revision`, `prefiltered`, `labels` and
`missing_reasons` in the named `provenance` list; leave unknown facts unresolved.
Retained declarations are unverified. Authenticate source releases, full
population coverage, joins, derived-tool versions, label and missing-reason
preservation against your conversion history before scientific review.

Keep local reports, aggregate counts, errors and source receipts private until
their disclosure is reviewed. This walkthrough provides no diagnostic export or
automatic publication. Once inputs and methods have the required evidence, use
the [workflow guide](WORKFLOW.md) for experimental factors, domains, models and
reviewed descriptive exports. Regression export, licensed annual validation,
workstation memory limits and independent analyst usability remain separate gates.
