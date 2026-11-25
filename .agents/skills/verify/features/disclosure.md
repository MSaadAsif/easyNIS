# Review disclosure

## Sub-features

Count distinct year-scoped hospitals and mask unweighted counts and weighted
estimates together, including complementary masking.

## How to get to it (user POV)

Call `nis_cell_counts(query, by = ...)` to aggregate a lazy DuckDB query.
Pass its unweighted and hospital-count columns and any weighted fields to
`nis_suppress()`.

## Driving it with Rscript

```sh
Rscript --vanilla .agents/skills/verify/drive.R disclosure
```

The companion cell includes a hospital number reused in two years. Verify
it counts as two year-scoped hospitals. At threshold one, the smallest cell
gets the count mask, the companion gets `Masked`, and the last cell remains
visible. Check both the count and estimate columns in `results.R`.

## Gotchas

Complementary masking covers the stated grouping only. Analysts must review
totals and quantities that can be derived from other published tables. For
the grouped data-frame policy, run the
[bounded check](../../disclosure-suppression/SKILL.md).
