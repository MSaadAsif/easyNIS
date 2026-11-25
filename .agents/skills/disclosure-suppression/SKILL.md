---
name: disclosure-suppression
description: Exhaustively check grouped data-frame suppression in easyNIS after changes to disclosure policy, masking columns, grouping, or complementary masking.
---

# Disclosure suppression

In a grouped data frame, `nis_suppress()` must mask counts and associated
estimates whenever either primary rule applies, and must apply complementary
masking within the specified stratum when enabled.

A missed mask can reveal a restricted cell directly or let a reader recover
it from a published total.

## Run

From the repository root, with R and the package imports available:

```sh
Rscript --vanilla .agents/skills/disclosure-suppression/check.R
```

The checker installs the checkout into a fresh library and exercises the
exported function. Expect `EXHAUSTIVE PASS 74368 input tables`, followed by
`RESULT PASS` and `CLEANUP PASS`. The printed evidence directory contains
the R and dependency versions, source hashes, and exact command. It lives
under the checkout's ignored verification directory.

A mismatch exits nonzero and writes `counterexample.R`. Read its threshold,
`secondary`, input, expected output, and actual output. Replay the input
through `nis_suppress()` with `count_col = "n"`, `weighted_cols = "estimate"`,
`by = c("case", "stratum")`, and `hospital_col = "hospitals"` if present.
If the single case passes, replay it in `batch-input.R` before ruling it out.
A mismatch with the product contract is a finding. Correct the checker
only when the expected result differs from the documented contract.

## Scope

No practical source verifier was identified for the R and dplyr path. The
checker enumerates the finite domain and calls the real installed R code.
It covers each ordered table of one through three rows, every way to
partition those rows into strata, integer discharge counts and thresholds
from zero through three, and integer hospital counts from zero through two
or an omitted hospital column. Both complementary settings are checked.
Each batch uses a case ID and a stratum ID as the grouping columns, so cases
can share a stratum label without sharing a group.

A count at or below the threshold takes precedence over the hospital mask.
When exactly one row in a stratum has a primary mask, complementary masking
selects the remaining positive row with the smallest count, breaking ties
in input order. The checker compares the entire returned data frame, including
displayed counts, hospital counts, weighted estimates, and grouping fields.

This is exhaustive only for the stated domain. It leaves ungrouped calls,
larger tables, malformed inputs, the survey-summary adapter, the calculation
of hospital counts, and recovery from published totals outside its scope.
The [workflow driver](../verify/features/disclosure.md) exercises the
ungrouped path and year-scoped hospital counting.

## Code and sync

The checker last matched package source at
`aefa33db24b73ce814f8bc14c91cae0d25f826d0`, using R 4.6.1 and dplyr 1.2.1.

- [R/suppress.R](../../../R/suppress.R) selects the data-frame path and validates the threshold.
- [R/disclosure-policy.R](../../../R/disclosure-policy.R) supplies the primary masks in `nis_disclosure_masks()`.
- [R/suppress-data-frame.R](../../../R/suppress-data-frame.R) selects companion rows in `complementary_suppress_rows()` and masks output fields in `suppress_dataframe()` and `apply_dataframe_suppression()`.

If these paths or their grouping dependencies change, compare the oracle in
[check.R](check.R) with the documented rules and run it against the checkout.
To show it still detects violations, run the four deliberate breaks against
an isolated archive of the current commit:

```sh
Rscript --vanilla .agents/skills/disclosure-suppression/mutations.R
```

This must catch an exclusive threshold, fewer hospital masks, missing
complementary masks, and a weighted estimate left visible. For an uncommitted
change, put the desired source and deliberate break in an isolated scratch
copy and pass that directory as the optional argument to `check.R`.
Rerun the unmodified check after mutation. Advance the sync commit only
after reviewing the covered source and confirming the unmodified result.
