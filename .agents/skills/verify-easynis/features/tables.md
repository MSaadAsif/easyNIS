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

Optional numeric grouping uses an exact factor field and an explicit missing-group
policy. Check ordered observed levels and unused-level provenance, independent WR
references including hospitals with no group members, outcome-specific missing
counts, standalone domain parity, preexisting domains and pooled reused IDs.
Review the complete grouped constructor result in one call and export its
presentation to CSV/HTML and supported Word. Verify repeated field statistics
share suppression within a domain while a safe other group stays shown.
Exercise independent unequal group partitions, cross-group protected pairs,
nested margins, group-specific binary scales, missingness and whole-table n
differences. Hospital unions count shared hospitals once and retain pooled
year-specific IDs. Reject inconsistent grouping provenance and retained group
membership. Internal identity keys, domain history and audit counts must stay
out of presentation and exports. Unreviewed numeric objects still refuse export.
Source cases live in `tests/testthat/test-grouped-disclosure.R` and
`tests/testthat/test-descriptive-table.R`. The installed six-year smoke path in
`tools/smoke-installed.R` uses factor -> grouped table -> one joint review ->
CSV/HTML, checking primary/complementary suppression, exact visible values,
formula defense, escaped text and repeatable output.

The full installed smoke runs this path for all six invented year labels.

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
That declaration must fail the whole review.
Two-level outcomes that differ by one floating-point step must retain their
separate count and hospital checks even if they print identically. Include a
small level across hospitals, a larger level in one hospital and a safe level,
reverse row order and exclude missing outcomes. CSV must hide suppressed values.
Check the documented limit of
one original-primary sum per relation and primary pairs; do not report full
subset certification. Source cases live in `tests/testthat/test-disclosure.R`;
the contract is `docs/DISCLOSURE.md`.

The same function reviews one unchanged `nis_regression_table()` with
`margins = list()`. Count every checked group by hand from the invented rows:
the model's included rows; each fitted model-matrix column's two levels or its
nonzero and zero-valued rows; every fitted factor or logical level,
including the reference and zero-count levels; and every cell, including
empty and reference cells, of the joint crossing of all factor, logical and
two-valued predictors, interacting or additive. Split every group into events
and nonevents for a binary (two-valued) response, or otherwise into
nonzero-response rows. Any two-valued response, such
as 1/2, must get the same response-value cells as its 0/1 coding. A
multi-valued response must check its nonzero rows like the descriptive review
of the same field, and a strictly positive response must stay shown. All-zero and
all-one non-intercept columns must follow the zero policy. Use distinct native hospital IDs,
including pooled reused IDs, against `min_hospitals`. Confirm a failed column
also hides the intercept, a failed factor hides its terms and their marginal
terms, a model failure hides every row and `unweighted_n`, and repeated terms
share status. Exercise the equal-weight one-binary-predictor logistic table
with each cell at 10 and 11 under `c(1, 10)`, a count of exactly 1, both zero
policies, a small reference cell in `event ~ group * sex`, a small
non-reference cell, a three-way crossing, an additive `event ~ group + sex`
saturated by an empty cell, missing exclusions
that drop a whole hospital, a domain and an average annual pool. Altered table values, declarations or class, nonempty
margins and export must be refused; caller objects must stay unchanged.
Presentation must hold only declared, inference and policy columns, with `NA`
for every hidden value and no audit counts. The installed smoke reviews a
small factor level and a logistic slope. Source cases live in
`tests/testthat/test-regression-disclosure.R`; the contract is
`docs/REGRESSION-DISCLOSURE.md`.

`nis_export_table()` writes a review's presentation to CSV, HTML or Word. Read the
CSV back with `utils::read.csv()` and compare every shown numeric value with
`identical()`; suppressed cells must be empty and audit fields absent. Check
that HTML escapes caller labels and units, records the policy notes, rounds
only to the requested significant digits and contains no suppressed value.
Compare exact and rounded exports with `OutDec` set to a point and a comma.
CSV/HTML bytes and Word cell text must match, with caller options unchanged.
Give a label beginning with `=` and an id beginning with `@`: `"refuse"`
must name both cells and write nothing, `"prefix"` must read back with a
leading `'`, and `"keep"` must write them unchanged.
Confirm that descriptive and regression tables, regression reviews and
modified reviews are refused, and that an existing file is replaced only with `overwrite = TRUE`.
Read Word output back with `officer::docx_summary()` and compare every cell
and note with the HTML export; search the unzipped XML for hidden values,
convert it to PDF with Word when available and inspect the layout. A label
with a control character must be refused, and a missing officer package must
give install guidance without writing.
Check that 24-, 25- and 120-character caller words retain their full text with
identical column widths, and that header words keep their nominal widths.
Exercise proportional scaling when protected text exceeds ten inches and lone
carriage returns in labels and units without changing the caller's review.
The installed smoke exports the subtotal reproduction in all three formats. Source
cases live in `tests/testthat/test-export.R`; the contract is `docs/EXPORT.md`.
