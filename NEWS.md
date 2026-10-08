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

## Experimental single-year design preparation

- Added `nis_survey_design()` with explicit population, hospital WR method and
  fail-on-singleton declarations, and a native `survey` design.
- Added `nis_domain()` with explicit logical-indicator missingness and retained
  full-design PSU information. Missing outcomes remain in the collected data.
- Retain raw identifiers and weights. Safely convert BIGINT weights for native
  probability calculations; reject precision-unsafe integers and nonfinite
  reciprocal weights. easyNIS does not set global survey options.
- Invented cases compare native totals and means against direct `survey` calls
  and hand-calculated variances including zero-domain hospitals. Annual support,
  pooled inference, model APIs and scientific approval remain pending.

## Experimental pooled-year design preparation

- Added `nis_pool_design()` for complete single-year designs with explicit
  combined-total, average-annual-total or pooled-proportion intent.
- Year-specific hospital and stratum keys prevent cross-year identifier reuse
  from collapsing the design. Original annual objects and raw weights remain.
- Only explicit average annual totals scale native weights by included years.
  Common analysis fields, classes and factor levels must agree.
- Independent synthetic calculations and direct native references cover varying
  annual weights, zero-domain hospitals, mean linearization and missing outcomes.
  Annual and scientific validation remain pending.

## Experimental scalar inference

- Added `nis_estimate()` for a scalar total, mean or zero/one proportion using
  native survey linearization, with explicit missingness, unadjusted hospital WR
  variance, confidence and interval degrees of freedom.
- Return numeric values, SE and Wald bounds alongside the native result, raw
  analysis design, exclusion counts and complete design provenance. Native
  domain and population degrees of freedom remain separate from caller choices.
- Preserve original PSU information when excluding NA/NaN outcomes. Reject
  empty analyses, infinite outcomes, unsafe BIGINT conversion and incompatible
  current survey options without altering caller settings.
- Enforce pooled total intent and label pooled means/proportions as weighted
  over included discharges. Independent synthetic WR calculations cover sparse
  domains, absent hospitals, missing outcomes, reused annual IDs and intervals.
  Annual support and scientific approval remain pending.
