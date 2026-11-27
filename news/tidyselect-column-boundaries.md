- Select columns in `nis_suppress()`, `nis_join_companion()`,
  `nis_audit_dx_position()`, and `nis_audit_code_transition()` with bare
  names, tidyselect helpers, or `all_of()` for a character vector. These
  selections and `nis_cell_counts(by = ...)` keep source names and resolve
  against the schema for lazy queries.
