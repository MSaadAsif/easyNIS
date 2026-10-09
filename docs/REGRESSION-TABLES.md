# Experimental numeric regression tables

This is the next bounded NIS-018 increment. It assembles existing coefficient
inference from one `nis_model` result; it does not fit a model or calculate new
statistics. Profile contrasts, exponentiated effects, grouped comparisons,
disclosure review and rendering remain separate capabilities.

`nis_regression_table(model, specification, scale)` requires `scale = "link"`.
`specification` is a nonempty plain data frame with exactly the plain character
columns `id`, `term`, `label` and `unit`, in any column order. All values must be
nonmissing and nonempty. IDs are unique; terms exactly match coefficient names
and may repeat with distinct IDs. Row order is retained. Labels and units are
caller declarations, not authenticated metadata or inferred interpretations.
An intercept or aliased coefficient can be requested explicitly.

The result is a `nis_regression_table` list with `data`, the original `model`,
unchanged `factors`, `sample`, `diagnostics`, and `provenance`. `data` contains
canonical declaration columns followed by the original numeric `estimate`,
`se`, `statistic`, `p_value`, `lower`, `upper`, and logical `aliased` values;
`coefficient_scale = "link"`, model `family` and `link`, explicit model `df` and
`confidence`, `raw_supplied`, `raw_included`, `raw_missing`,
`weighted_denominator`, `analysis_hospitals`, and `disclosure_status`.
Use distinct native first nested cluster IDs for hospital counts. Do not round,
format, exponentiate, replace NA/NaN inference or manufacture reference rows.
All existing coefficient numbers and missing inference remain exact.

Factor coding remains explicit in `factors`: fitted levels, fixed contrast
matrices, ordered status and zero-coded levels are preserved unchanged.
Treatment, sum, polynomial and interaction coefficients must not be assigned
an invented universal reference group. The complete formula, response scale,
offset, constructor, domain, missingness, inference policies and fitting
diagnostics remain available in the retained model and provenance. Intervals
are pointwise; coefficient null tests are the existing link-scale zero tests.
An odds, mean or rate interpretation must never be inferred from a label/unit.
Nonconverged or boundary fits may be inspected on their existing link scale;
their original diagnostics are retained without certifying them.

Provenance records the canonical declarations, link scale and pointwise
interval scope, original model provenance and the table scope
`experimental_numeric_regression_table`, with `analysis_ready = FALSE`.
Disclosure status remains `unreviewed`. Caller models, specifications, raw
columns and options remain unchanged. Invalid declarations reject the whole
call. No annual support or scientific approval is promoted.

Verification must use the installed public API on invented data, preserving
exact values against the original coefficient table and separately established
Gaussian and quasi-family references. Cover intercepts, factors and interaction
coding, aliases, zero/undefined inference, transformed responses, exposure
offsets, nonconverged diagnostics, missingness and whole-hospital exclusion,
domains and average annual pools with reused hospital identifiers, finite and
infinite df, repeated/quoted terms, reordered declarations, malformed schema,
invalid scales and unchanged caller state. Extend the installed smoke and
table feature recipe. This contract adds no new inferential calculation.
