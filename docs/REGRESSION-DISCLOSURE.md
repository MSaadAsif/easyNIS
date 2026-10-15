# Experimental disclosure review for regression tables

This is the next bounded NIS-019 increment. It extends
`nis_disclosure_review()` to one unchanged `nis_regression_table()` result.
Export of the reviewed regression presentation remains a separate NIS-020
increment; `nis_export_table()` continues to refuse regression reviews until
then. The review assists a human publication check. It does not certify a
manuscript, approve the policy or promote annual support.

## Why counts matter for coefficients

A coefficient table publishes no cell counts, but its numbers can determine
them. In an unweighted or equal-weight logistic model with one binary
predictor, the intercept, slope and their standard errors determine all four
predictor-by-outcome cell counts. A factor level or reference level containing
a few discharges yields a coefficient that describes those discharges. The
review therefore checks the unweighted analysis-sample groups underlying each
published coefficient, using the caller's explicit policy.

## Interface

`nis_disclosure_review(table, suppress, zero, min_hospitals, margins)` keeps
its existing arguments and meanings for `suppress`, `zero` and
`min_hospitals`. For a regression table:

- `table` is one unchanged `nis_regression_table`. Its coefficient columns
  must equal the retained model's coefficient table, and its declarations
  must match the retained provenance; altered objects are refused.
- `margins` must be `list()`. Coefficients are not additive counts, so margin
  relations are refused rather than ignored.

Descriptive-table reviews, their results and export bytes remain unchanged.

## Checked groups

Every count is unweighted and taken from the model's included analysis rows,
after outcome/predictor missingness and whole-hospital exclusions. Hospitals are
distinct native first-level cluster identifiers among those rows, so pooled
reused identifiers remain distinct by year. Each count uses the existing range
and zero policy; each nonempty group also needs at least `min_hospitals`
contributing hospitals. Two values are distinct only under exact numeric
equality.

A response is binary when it is logical or every included value is 0 or 1.

1. Model checks. The included count and its hospitals. For a binary response,
   the event and nonevent counts and their hospitals. Any failure suppresses
   every row (`model:<check>`).
2. Coefficient column checks, using every fitted model-matrix column,
   declared or not:
   - A constant column, such as the intercept, has no checks of its own.
   - A column with exactly two distinct values checks both level counts
     (`lower_level`, `upper_level`). With a binary response, it also checks the
     four level-by-outcome cells (`lower_level_events`,
     `lower_level_nonevents`, `upper_level_events`, `upper_level_nonevents`).
   - A column with three or more distinct values checks its nonzero count and,
     when present, its zero-valued count (`nonzero`, `zero_valued`).
   A failure suppresses that column's rows (`column:<check>`, or
   `column:hospitals_<check>` for a hospital failure). It also suppresses the
   rows of every constant column (`reference:<term>`), even when the failed
   column is undeclared or aliased.
3. Factor checks. For each factor or logical predictor in the fitted model
   frame, every fitted level is checked, including the reference level and
   levels with zero included rows. With a binary response, each
   level-by-outcome cell is also checked. A failure suppresses every row whose
   column belongs to a model term containing that predictor, including
   interactions, and every row whose term's variables all lie within such a
   term: the intercept, and a main effect that an interaction with the
   predictor makes level-specific (`factor:<variable>`). Factor levels come
   from the retained fit; no reference group is inferred from labels.
4. Repeated terms. Rows declaring the same coefficient name share one fitted
   column, so they receive the same reasons and status.

No margin, protected-sum or missing-outcome differencing repair applies,
because one model has one analysis sample and the coefficients are not
additive counts.

### Implementation choices

These conservative choices were recorded while implementing the contract:

- Constant columns describe the group where every other column is zero. With
  equal weights and one binary predictor, the intercept and its standard error
  determine the two reference-group cells, so a failed column check also hides
  constant columns. All fitted columns are checked so that an undeclared
  failing column still protects a declared intercept.
- In a model such as `y ~ x * group`, the `x` coefficient is the slope within
  the reference level of `group`. A failed factor therefore also hides the
  lower-order terms within each term containing it, not only those terms.
- Rows repeating a term share a fitted column and therefore identical checks,
  so no separate `term:<name>` reason is needed.
- `nis_model()` refuses character predictors, so only factor and logical
  predictors arise. A fitted frame whose factor or logical predictors or levels
  differ from the retained `factors` is refused.
- The response is the fitted model response, so a transformed Gaussian
  response is binary only when its transformed values are zero or one.

## Result

The result keeps the `nis_disclosure_review` class, with `presentation`,
`audit`, the unchanged `table` and `provenance` recording the policy and
`table_kind = "regression"`. The presentation keeps the declared `id`, `term`,
`label` and `unit`, the coefficient inference columns `estimate`, `se`,
`statistic`, `p_value`, `lower`, `upper` and `aliased`, then
`coefficient_scale`, `family`, `link`, the model `df` and `confidence`, the
model included count as `unweighted_n` and a `disclosure_status` of `shown` or
`suppressed`. Suppressed rows carry `NA` for every inference value, including
`aliased`, because an aliased all-zero column can reveal an empty level.
`unweighted_n` is `NA` when a model check fails. Raw supplied/missing counts,
per-group counts, hospital counts and reasons stay in the local audit and are
never presentation columns. The audit is a list: `sample` (supplied, included
and missing rows, hospitals and whether the response is binary), `groups` (one
row per checked group with its scope, target, check, level or column value,
outcome, count, hospitals and failures) and `rows` (each declared row's reasons
and status). `nis_export_table()` refuses regression reviews.

## Limitations

The bounded checks do not address differencing across separately fitted models
or tables, weights that are themselves disclosive, offsets, continuous-predictor
extremes, or information recoverable from covariance matrices beyond the
published standard errors. The procedure is conservative within these checks,
not minimal, and not a disclosure certification. Saad and Ali must review the
policy and any applicable agreement before publication.

## Acceptance cases

Verification uses invented data, an independent hand-counted reference for every
checked group and the installed public API. Cover: gaussian and binomial fits;
the equal-weight one-binary-predictor logistic case with each of the four cells
just inside and outside the range; a small reference level and a small
non-reference level; zero-count fitted levels under both zero policies; a
factor-by-continuous interaction; a two-valued non-0/1 column; a continuous
column with few nonzero values; minimum hospitals for model, column and factor
groups; model-level failure suppressing every row; repeated and reordered terms;
domains and an average annual pool with reused hospital identifiers; logical
predictors; aliased coefficients; nonempty margins refused; altered table
values, declarations or class refused; unchanged caller objects; unchanged
descriptive reviews; and continued export refusal. Extend the installed smoke
and the tables feature recipe.
