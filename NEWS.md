# easyNIS 0.0.0.9000

- Started an installable development package with generated help and namespace.
- Added `nis_supported_years()` with separate roadmap and capability states.
- Added `nis_synthetic_data()` with entirely invented component records for
  2017–2022 labels and hand-calculated point-summary expectations.
- Added offline examples, fixture tests, source-tarball inspection, and R check CI.
- No licensed-data years, importers, or statistical methods are supported yet.

## Experimental structural import

- Added owned DuckDB sessions, lazy local parquet component imports, and
  explicit column collection.
- Reject mismatched shards, mixed years, ambiguous names, unsafe component keys,
  unmatched core rows, and conflicting shared fields.
- Added aggregate structural validation reports for keys, weights, and code
  types. Raw values are retained and analysis approval remains false.
- Added tests for component joins, SQL quoting, connection cleanup, source
  deletion and modification-time changes, and exact BIGINT collection.
- Reject unsafe decimal or wide numeric identifier collection before R can
  round values. String identifiers must contain positive decimal digits.
- Structural field/year/join failures provide machine-readable conditions with
  check, component, fields, and affected counts, without discharge identifiers.

## Experimental code matching

- Added versioned user-declared code sets with syntax checks, explicit coding
  system, year and quarter applicability, and source/author provenance.
- Added literal exact or prefix flags for principal, secondary, all diagnosis,
  and procedure scopes. Missingness policy and selected slots are explicit.
- Flags retain every discharge, preserve the original relation, and record
  common-slot versus observed-slot selection. Restricted quarters are unknown
  outside their declared periods.
- Invented tests compare SQL results with R and expose cross-year slot
  sensitivity. No clinical phenotypes or annual dictionaries are validated.
- Validate nonmissing observed code syntax before matching. Normalization is
  specific to coding system and uses the same ASCII whitespace rule in R/SQL.
  Malformed source strings cannot be repaired into positive matches.

## Lazy selections and field status

- Added `nis_select()` to narrow a relation without collecting or filtering
  discharges. Exact selected columns and imported schema are retained.
- Structural validation now distinguishes present fields, fields removed by
  caller selection, and absences whose source/conversion reason is unverified.
  Requested SQL NULL counts remain separate from unknown absent-field counts.
- Imported fields and dropped flag definitions retain their provenance and
  cannot be overwritten by reusing their names, including case variants.
  Annual missing-value interpretation remains pending.
