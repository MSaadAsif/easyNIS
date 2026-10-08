# Experimental pooled-year design preparation

`nis_pool_design()` pools complete single-year `nis_survey_design()` results,
then `nis_domain()` may select a logical domain. Previous domains, pooled
inputs, repeated years and incompatible method declarations are refused.
This advances the invented-input portion of NIS-014 without annual approval.

Require an explicit `estimand` and common analysis `columns`. Every requested
column must be present in every annual design, with matching classes and factor
levels. The package does not guess annual mappings or silently drop an absent
analysis field. Original annual designs remain available in `annual_designs`,
including raw identifier and weight types and source/provenance receipts.

## Estimand and weight policy

| Declared intent | Native weights | Interpretation of appropriate native result |
|---|---|---|
| `combined_total` | Annual supplied weights | Sum over the included years. |
| `average_annual_total` | Annual weights divided by the number of supplied years | Arithmetic average of annual totals over included years. |
| `pooled_proportion` | Annual supplied weights | Weighted proportion among included discharges. |

Included years and the exact weight divisor are recorded. Missing years are
not invented. A pooled proportion is not the arithmetic average of annual
proportions. Native calls remain the caller's responsibility; an intent label
does not prevent arbitrary native calls or approve a different interpretation.
Missing outcome and inference policies remain explicit downstream decisions.
The experimental [scalar estimate API](ESTIMATES.md) enforces total intent and
records weighted pooled interpretations for means and proportions.

## Exact annual identity

Previously validated year and hospital/stratum identifiers form unambiguous
year-specific design keys before native construction. Reusing a hospital,
stratum or discharge-key value in another year cannot collapse PSUs or strata.
The pooled projection represents identifier columns as exact strings. Original
annual objects preserve their raw values and types. No annual weight is changed
in the raw pooled DISCWT column, even when native weights are explicitly scaled.

The method remains hospital-cluster WR with no FPC and no global option changes.
Initial survey options, versions and annual provenance are recorded. Historical
trend weights, year-composition decisions and approved inference require their
own gates. The eager implementation has no benchmarked memory envelope.

The pooled policy follows the agreed [analysis contract](PLAN.md) and is
informed by the combining-years discussion in
[HCUP Methods Series 2015-09](https://hcup-us.ahrq.gov/reports/methods/2015-09.pdf),
printed page 14. Source layouts, conversion profiles and author review remain
necessary for annual support.

## Independent reference cases

Two invented years reuse identifiers and have four hospitals in two strata per
year. Second-year weights are twice the first-year weights. Domains occur in
one hospital per stratum. Weighted LOS contributions are 22 and 22 in the first
year and 56 and 56 in the second. The combined domain total is 156 with WR
variance 7240. The average annual total is 78 with variance 1810. Domain weights
total 54; the mean is 156/54 with variance 64/54^2. The pooled logical proportion
is 0.5 with variance 810/108^2. These separate hospital-level calculations and
direct native year-keyed survey references use tolerance 1e-12 for small,
deterministic double calculations.

Tests preserve missing outcomes and exact BIGINT identifiers, reject repeated
or already selected inputs and incompatible fields/levels, and retain caller
options. No installed annual capability or scientific approval is promoted.
