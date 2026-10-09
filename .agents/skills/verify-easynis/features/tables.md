# Numeric descriptive tables

Drive `nis_descriptive_table()` through the installed package. Use a plain
declaration data frame with exact retained fields and explicit statistic,
missingness, interval and variance policies. Check mean, proportion and total
rows against independent hospital-level WR arithmetic. Include a repeated
field with separate IDs, differing missingness, a quoted field name, a domain,
and a pooled design whose reused hospital IDs remain distinct by year.

Confirm output row order, exact unrounded scalar values, named native results,
per-row counts and denominators, complete constructor/domain provenance, and
`analysis_ready = FALSE`. Exercise zero estimates, finite and infinite df,
proportion units, malformed declarations, infinite outcomes and a failing row.
Verify a failed row rejects the complete call and leaves caller inputs/options
unchanged. Disclosure status must remain `unreviewed`.

The full installed smoke runs this path for all six invented year labels. Source
cases live in `tests/testthat/test-descriptive-table.R`; the smoke path is
`tools/smoke-installed.R`.

`nis_regression_table()` selects exact existing coefficient rows from one
`nis_model()` and requires `scale = "link"`. Keep repeated terms under distinct
IDs when needed, and inspect retained `factors` and model provenance before
assigning caller labels. Compare all numeric columns directly with the fit's
coefficient table, including aliased and undefined inference; confirm sample
counts, native hospital IDs, diagnostics and unchanged model. The installed
smoke exercises regression tables for all six invented year labels and checks
the pooled distinct-hospital count. Source cases live in
`tests/testthat/test-regression-table.R`.
