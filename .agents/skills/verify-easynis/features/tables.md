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

`nis_disclosure_review()` reviews one descriptive table under an explicit
range, zero policy, hospital minimum and declared margins. Check statuses
against counts computed independently from the invented rows, never from
weighted estimates. Confirm shown presentation values equal the numeric table,
suppressed values are `NA`, and `presentation` has only its documented columns
and no extra attributes. Include counts 0, 1, 9, 10 and 11, a large weighted
total from few raw rows, one contributing hospital, binary complements, missing
counts, margin recovery and a small suppressed pair. The installed smoke runs a
review for all six invented year labels and sources the installed public
`examples/disclosure-subtotals.R` reproduction. Confirm that two combined
relations cannot publish all, S and E when their difference recovers a
seven-discharge primary-hidden pair. Keep the same check for three original
primary parts and for a pair without a shared relation. Exercise hospital-only
and zero sums, a two-level group of 12 discharges in one hospital, and a
declaration that forces a hidden zero independently of published values.
That declaration must fail the whole review. Check the documented limit of
one original-primary sum per relation and primary pairs; do not report full
subset certification. Source cases live in `tests/testthat/test-disclosure.R`;
the contract is `docs/DISCLOSURE.md`.

`nis_export_table()` writes a review's presentation to CSV or HTML. Read the
CSV back with `utils::read.csv()` and compare every shown numeric value with
`identical()`; suppressed cells must be empty and audit fields absent. Check
that HTML escapes caller labels and units, records the policy notes, rounds
only to the requested significant digits and contains no suppressed value.
Confirm that descriptive and regression tables and modified reviews are
refused, and that an existing file is replaced only with `overwrite = TRUE`.
The installed smoke exports the subtotal reproduction in both formats. Source
cases live in `tests/testthat/test-export.R`; the contract is `docs/EXPORT.md`.
