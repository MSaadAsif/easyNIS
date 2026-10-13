# Explicit analysis factors

`nis_factor(design, field, name, levels, labels)` adds one unordered analysis
factor to an existing full, pooled or domain design. It replaces manual edits
to the native design's data frame and records the declaration, advancing the
caller-declared analysis portion of NIS-010/016/021 without introducing canonical
annual mappings or new inference methods.

```r
analysis <- nis_factor(design, "group", "group_factor", c(0, 1),
  c("Comparator", "Exposed"))
batch <- nis_models(analysis, c(binary = "quasibinomial", stay = "gaussian"),
  ~ group_factor + age, "exclude", 6, 0.95, "wr_unadjusted")
batch$sample
batch$models$binary$factors
```

All raw allowed levels and distinct nonblank labels are explicit, in the desired
order. Levels must have the source's numeric/logical/character kind and be unique
and nonmissing. Numeric matching uses the stored numeric values directly; it
does not format them to text first. Classed fields, matrices and observed numeric
infinities are refused. A new target must not collide with existing fields,
including case variants, or the native model's reserved names.

An observed value absent from the declaration rejects the entire call with
`nis_factor_error`, its exact source `field` and aggregate `affected` count.
No record values appear in that error. Source NA and NaN remain missing in the
new factor; source strings such as `"NA"` remain ordinary declared categories.
Negative numeric sentinels are ordinary observed values: declare them explicitly
or obtain a separately reviewed missing-code contract. This helper does not
drop rows, impute values, collapse levels or turn unknown codes silently into NA.
Unused declared levels and a single declared level are retained; that does not
establish that a subsequent model has enough supported levels to fit.

The original raw field and all other columns remain intact. Native cluster,
stratum, weight and PSU information, population and sequential domain history
are unchanged. `provenance$analysis_transforms` appends the raw-level/label/target
declaration with `mapping_status = "caller_declared_unverified"` and
`raw_preserved = TRUE`; `provenance$columns` lists the resulting columns.
All earlier provenance is retained and `analysis_ready` remains FALSE.

No contrasts or global options are changed. Level order alone does not promise
a universal reference group: treatment, sum and other contrast choices have
different meanings, and complete-case exclusion can remove declared levels.
Inspect each fitted model's factor matrices, zero-coded levels, missingness and
observed support diagnostics. Do not present a dropped or unobserved category
as a fitted reference. Existing [model](MODELS.md) restrictions and diagnostics
still apply. Derived-variable meanings, clinical labels, special missing reasons,
licensed annual validation and scientific/publication approval remain separate.

Acceptance cases cover numeric/logical/character sources, exact numeric matches,
NA/NaN and literal NA labels, unused/one-level declarations, whole-call rejection,
raw/design/options preservation, sequential declarations, factor predicates,
single/domain/pooled designs and per-model missingness. Model coding/covariance
must match separately constructed factors and independent numerical references;
the installed drive must use the real public helper and retain raw fields.
