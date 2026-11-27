# 0001. In-database survey estimation

## Status

Accepted

## Context

Whole-sample estimation at about six NIS years exceeds the 8 GB, 4-core
minimum profile with both an in-memory `survey` or `srvyr` design and
`survey`'s `DBIsvydesign`. The whole-sample quasibinomial in-memory control
peaked at about 18.5 GB of process commit, and the wide in-memory controls
hit a 22 GiB R vector-heap cap. The DBI design also failed the invented-data
`gtsummary::tbl_svysummary()` compatibility check.

## Decision

Add a Taylor-linearization engine for whole-sample and large-domain totals,
means, grouped estimates (`svyby()`), and canonical-link GLMs. Limit the
model families to Gaussian with identity, binomial or quasibinomial with
logit, and Poisson or quasipoisson with log. DuckDB reads the Parquet views
directly and computes the sums by primary sampling unit (PSU). R finishes
the calculation from the aggregates. Keep zero contributions from
out-of-domain PSUs in the variance calculation.

Return `svystat`-, `svyby`-, and `svyglm`-compatible results that support
`coef()`, `SE()`, `vcov()`, and `confint()`. Model results must also work
with broom and `gtsummary::tbl_regression()`. Cohort-scale analysis uses
`nis_design()` with `survey`, `srvyr`, and `gtsummary`. Quantiles, chi-square
tests, `tbl_svysummary()`, and inverse probability of treatment weighting
(IPTW) use the row-level workflow.

The package engine must meet these requirements from independent review:

- Apply explicit rank and conditioning tolerances to the weighted Gram
  matrix before inversion. Default pivoted Cholesky tolerance accepted a
  near-collinear predictor that the reference QR fit dropped.
- Center and scale GLM predictors and outcomes where the model family permits
  it, and return results on the original scale. Extreme offsets degraded
  agreement.
- Support grouping keys across the types accepted by `svyby()`. Cast raw
  DuckDB `DECIMAL` operands inside expressions before arithmetic.
- Support `survey.lonely.psu` settings `"fail"` and `"adjust"`. Reject
  other settings explicitly.
- Require relative agreement within `1e-8` on invented data and `1e-6` on
  licensed data against independent `survey` calls with default settings.

## Consequences

Keep the second estimation path small and use `survey` as its sole numerical
reference. The package design still needs a reliable rule for selecting
the estimation path or an explicit verb for choosing it. The five-year
wide whole-sample quasibinomial fit takes about 7.5 minutes on the minimum
profile, mostly spent rescanning Parquet during iteratively reweighted
least squares.

## Evidence

- `1d06879` records the Q26 backend comparison and the invented-data
  `gtsummary` compatibility check.
- `a6bb978` records the in-database prototype and its verification harness.
  Across five-year workloads on the four-thread minimum profile, direct
  Parquet views used at most 0.82 GB of peak process commit. Wide temporary
  tables peaked at 5.38 GB and were 17% faster on the slowest model.
