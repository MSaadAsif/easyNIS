# Experimental numeric descriptive tables

This is the bounded first NIS-018 contract. Regression tables, grouped-table
comparisons, disclosure review and rendering remain separate increments.

`nis_descriptive_table(design, specification, missing, df, confidence, variance)`
calculates explicitly requested scalar statistics on one existing experimental
single-year, pooled or domain design. Every inference policy is explicit and
has the meaning documented in [ESTIMATES.md](ESTIMATES.md). Each row delegates
to `nis_estimate()` without changing its native design, variance, interval,
missingness or pooling rules.

## Row declarations

`specification` is a nonempty plain data frame with exactly the character
columns `id`, `field`, `statistic`, `label` and `unit`. Column order may vary;
row order is retained. IDs are unique and labels/units are caller declarations.
All values are nonmissing and nonempty. Fields match exact retained names.
Statistics are `mean`, `proportion` or `total`. A field can appear in more than
one row with distinct IDs. Proportions retain their native zero-to-one scale
and require the unit `proportion`; the function does not multiply by 100.
Other units are explicitly supplied and are not authenticated against annual
metadata or a field's name. No reference group or between-group comparison is
inferred. The design's complete domain history remains in provenance.

Missing exclusion is per field, so rows can have different analysis samples
and weighted denominators. Excluded counts overlap across rows and must not be
summed to obtain a distinct-discharge exclusion count. Intervals are pointwise
Wald intervals using the shared explicit df/confidence, not simultaneous
intervals. A failing row rejects the call without returning a partial table.
The design, raw columns, caller options and existing result objects are not
modified.

## Numeric output and evidence

The `nis_descriptive_table` result contains a plain numeric `data` frame with
the declarations plus `estimand`, `weighted_estimate`, `se`, `lower`, `upper`,
`df`, `confidence`, `raw_supplied`, `raw_included`, `raw_missing`,
`weighted_denominator`, `analysis_hospitals` and `disclosure_status`.
Values are unrounded and unformatted. Raw rows describe discharges, not unique
patients. Hospital counts use distinct native first nested cluster identifiers
among included rows, keeping reused annual hospital IDs distinct in pools.
The original `nis_estimate` objects are retained in `results`, named by row ID,
including native estimates/designs and complete source/domain provenance.
The table also retains the declarations and inference policies in provenance.

These are internal numeric tables with disclosure status `unreviewed` and
`analysis_ready = FALSE`. They do not apply suppression, serialize results,
approve publication or promote annual support. Downstream disclosure and
rendering must enforce their own acceptance criteria before publication.

Verification must exercise the installed public interface on invented data.
Independent hospital-level arithmetic must check weighted means, proportions,
totals and intervals; cases must cover differing field missingness, zero
results, repeated fields with different statistics, exact quoted names,
single-year/domain/pooled interpretations, year-specific hospital counts,
declaration failures and caller-state preservation. Native results must remain
available and table values must exactly preserve their numeric values.
