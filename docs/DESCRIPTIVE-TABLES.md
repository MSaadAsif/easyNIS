# Experimental numeric descriptive tables

This is the bounded NIS-018 numeric contract with NIS-035 factor grouping.
Regression tables and between-group comparisons remain separate increments.

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

Optional `by` accepts only an exact retained standard unordered factor.
`group_missing` must explicitly choose `fail` or `exclude`; supplying it without
`by` is an error. Observed levels follow the factor's declared order. Empty and
all-missing group selections fail, and unused declared levels create no rows.
Grouping provenance records the field, observed and unused levels, unknown
membership count and policy. Each group is selected through `nis_domain()` on
the supplied current design, preserving full-population and PSU information.
Grouped IDs use `g1.`, `g2.` and so on before each declared ID; labels append
`| field = level`. Outcome missingness remains independent within each group.
Each estimate retains its native domain result and complete domain history. A
failure anywhere rejects the whole grouped call.

Grouped tables remain numeric analysis objects until one joint
`nis_disclosure_review()` reviews the complete constructor result. The review
distinguishes exact fields and complete group-domain histories while keeping
repeated statistics together within each domain. Its presentation can use the
existing CSV, HTML and Word adapters. No overall row or between-group inference
is produced, and separately constructed tables cannot be combined by this API.

These are internal numeric tables with disclosure status `unreviewed` and
`analysis_ready = FALSE`. They do not apply suppression, serialize results,
approve publication or promote annual support. [DISCLOSURE.md](DISCLOSURE.md)
describes the separate experimental review; rendering must enforce its own
acceptance criteria before publication.

Verification must exercise the installed public interface on invented data.
Independent hospital-level arithmetic must check weighted means, proportions,
totals and intervals; cases must cover differing field missingness, zero
results, repeated fields with different statistics, exact quoted names,
single-year/domain/pooled interpretations, year-specific hospital counts,
declaration failures and caller-state preservation. Native results must remain
available and table values must exactly preserve their numeric values.
Grouped verification also compares independent hospital WR means, proportions
and totals when hospitals contribute no group observations; checks exact domain
parity, factor order, unused and missing groups, pooled reused IDs and current
domains; and drives one joint review and presentation-only exports with primary
and complementary suppression. Unreviewed numeric objects still refuse export.
