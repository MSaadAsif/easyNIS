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
  changes, and exact BIGINT collection.
