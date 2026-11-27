## New features

- Table inputs to `nis_label()`, `nis_cost()`, `nis_cost_provenance()`,
  `nis_join_companion()`, `nis_write_cohort()` and `nis_suppress()` use
  `.data`. In `nis_ccsr_codes()`, supply categories first and pass a custom
  mapping by name with `file =`.
- Use `nis_audit_dx_position()` for diagnosis-position sensitivity and
  `nis_audit_prday()` for procedure-day completeness. To add position flags
  to records, use `nis_flag_dx()` for each position and derive a
  secondary-only flag with `any & !principal`.

- `nis_example()` includes discharge keys for lazy comorbidity scoring.
  `nis_add_ccsr()` keeps the query's source information so an enriched
  cohort can be saved and reopened.
- `nis_cell_counts()` accepts tidyselect expressions in `by` and returns
  overall counts when `by` is omitted.
