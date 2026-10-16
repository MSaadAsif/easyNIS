# Experimental disclosure review for regression tables

This NIS-019 increment extends `nis_disclosure_review()` to one unchanged
`nis_regression_table()` result. Export of the reviewed regression
presentation remains a separate NIS-020 increment; `nis_export_table()`
continues to refuse regression reviews until then. The review assists a human
publication check. It does not certify a manuscript, approve the policy or
promote annual support.

## Why counts matter for coefficients

A coefficient table publishes no cell counts, but its numbers can reveal
them. In an unweighted or equal-weight logistic model with one binary
predictor, the intercept and slope give the within-group event proportions,
and model-based standard errors would determine all four predictor-by-outcome
cell counts. The design-based standard errors that easyNIS publishes do not
determine them exactly but can still reveal them. A factor level, reference
level or interaction cell containing a few discharges yields coefficients that
describe those discharges, much as a descriptive mean of that group would.

The review therefore applies one rule: each checked group receives the
descriptive row checks on its own response values, both the fitted response
and, for a transformed response, each raw source field. The checked groups are the
model sample, each fitted model-matrix column's groups, each fitted factor or
logical level and every cell of the joint crossing of all factor, logical and
two-valued numeric predictors. The caller's explicit policy applies
throughout. The review does not check every group a fitted model implicitly
depends on; see the limitations.

## Interface

`nis_disclosure_review(table, suppress, zero, min_hospitals, margins)` keeps
its existing arguments and meanings for `suppress`, `zero` and
`min_hospitals`. For a regression table:

- `table` is one unchanged `nis_regression_table`. Its coefficient columns
  must equal the retained model's coefficient table, and its declarations
  must match the retained provenance; altered objects are refused. A table
  that matches its retained model, but whose retained fit, coefficients or
  factors are internally inconsistent, is refused with a separate message.
- `margins` must be `list()`. Coefficients are not additive counts, so margin
  relations are refused rather than ignored.

Descriptive-table reviews, their results and export bytes remain unchanged.

## The group rule

Every count is unweighted and taken from the model's included analysis rows,
after outcome/predictor missingness and whole-hospital exclusions. Hospitals are
distinct native first-level cluster identifiers among those rows, so pooled
reused identifiers remain distinct by year. Two values are distinct only under
exact numeric equality.

The fitted model response is checked on its fitted values. A fitted response
with exactly two distinct values that are not 0/1 (for example 1/2, 0/2 or
-1/1) is first recoded to 0/1, with the upper value as 1. Every coding of a
two-valued outcome therefore receives the same checks as its 0/1 coding.

A transformed response, such as `I(y + 1)`, `I(y - 5)` or `log1p(y)`, can move
zeros or merge values, so each raw source field named by the model
(`response_fields` in its provenance) is also checked. Its values are taken
from the retained design variables over the same fitted rows, with the
descriptive value semantics of [DISCLOSURE.md](DISCLOSURE.md) (logical values
as 0/1, no recoding). Its splits are named with `source_`, for example
`source_nonzero` or `level_source_zero_valued`, and the audit records the field
in `source`. A named outcome is its own source field, so it is checked once.

For a group of rows and each response vector `y` above, the descriptive row
checks of [DISCLOSURE.md](DISCLOSURE.md) are applied to `y` restricted to the
group:

- its size, under the range and zero policies;
- when nonempty, its rows with a nonzero response (`nonzero`), under the range
  and zero policies;
- when the group's own values are all 0 or 1, its zero-valued rows
  (`zero_valued`), under the range and zero policies;
- otherwise, when the group has exactly two distinct values, its smaller level
  (`two_level`), under the range only, as in the descriptive review;
- for each nonempty one of these, at least `min_hospitals` contributing
  hospitals (the smaller of the two levels' hospital counts for `two_level`).

Whether a group is zero/one or two-valued is decided from that group's own
values, exactly as a descriptive row decides it from its included values. An
empty group is checked on its zero size alone. Within a group, check names
join the group name and the split, for example `level_zero_valued` or
`cell_nonzero`; for the model sample the splits are plain `nonzero`,
`zero_valued` and `two_level`.

1. Model sample. The group rule applies to all included rows (`included`). The
   count of rows excluded for missingness in any model field (`missing`) is
   checked against the range only. This combined count differs from a
   descriptive row's count of missing outcomes: when predictors are also
   missing, a combined count above the range can pass while the outcome-only
   count would fail, and it is the combined count that `unweighted_n` and the
   supplied count reveal. Any failure suppresses every row and
   `unweighted_n` (`model:<check>`); a failed missing check suppresses the
   rows, as the descriptive review suppresses its row, because `unweighted_n`
   and the supplied count together reveal it.
2. Coefficient columns, using every fitted model-matrix column, declared or
   not:
   - The intercept has no groups of its own. Any other constant column forms
     its nonzero group, and a constant nonzero column also its zero-valued
     group, so an empty interaction cell, an indicator that is zero for every
     analysis row and an indicator equal to one on every row each have an
     empty group under the zero policy.
   - A column with exactly two distinct values forms both level groups
     (`lower_level`, `upper_level`).
   - A column with three or more distinct values forms its nonzero group and,
     when present, its zero-valued group (`nonzero`, `zero_valued`).
   Each group receives the group rule. A failure suppresses that column's rows
   (`column:<check>`, or `column:hospitals_<check>` for a hospital failure). It
   also suppresses the rows of every constant column (`reference:<term>`),
   even when the failed column is undeclared or aliased.
3. Factor levels. For each factor or logical predictor in the fitted model
   frame, every fitted level, including the reference level and levels with
   zero included rows, is a group receiving the group rule (`level`,
   `level_nonzero`, `level_zero_valued`, `level_two_level`). A failure
   suppresses every row whose column belongs to a model term containing that
   predictor, including interactions, and every row whose term's variables
   all lie within such a term: the intercept, and a main effect that an
   interaction with the predictor makes level-specific (`factor:<variable>`).
   Factor levels come from the retained fit; no reference group is inferred
   from labels.
4. Joint cells. When the model has two or more factor, logical or two-valued
   numeric predictors, every cell of the full joint crossing of all of them,
   whether they interact or enter additively, is a group receiving the group
   rule (`cell`, `cell_nonzero`, `cell_zero_valued`, `cell_two_level`). Cells
   use fitted factor levels and the observed two values, and include the
   reference cell and empty cells. A failing cell suppresses the rows of every
   term containing any crossed predictor and the lower-order terms within
   them, including the intercept (`cross:<variables>`). A crossing of more than
   10000 cells is refused rather than reviewed. Numeric predictors with three
   or more distinct values are not crossed.
5. Repeated terms. Rows declaring the same coefficient name share one fitted
   column, so they receive the same reasons and status.

No margin or protected-sum repair applies, because one model has one analysis
sample and the coefficients are not additive counts.

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
- Recoding a two-valued fitted response to 0/1 checks both levels under the zero
  policy. This covers the descriptive `two_level` check of a group with both
  values and also checks a group lacking one value.

### Review-driven changes

Four independent reviews each found an unchecked group.

1. Interaction cells were not crossed: in `event ~ group * sex` a 3-row
   reference cell was disclosed by the intercept. All-zero non-intercept
   columns bypassed the zero policy.
2. A 1/2-coded response skipped its outcome cells, and an empty B/M cell made
   the additive `event ~ group + sex` saturated, so its intercept was exactly
   the logit of a 3-row A/F cell. Joint crossing of all categorical
   predictors and the two-valued recoding replaced case-by-case rules. Joint
   crossing suppresses more than necessary in additive models with many
   categorical predictors, and empty joint cells under `zero = "suppress"`
   hide every crossed term; both are accepted as conservative.
3. A response with three or more distinct values had no response checks, so
   `y ~ 1` with 3 of 100 nonzero values was shown although the descriptive
   review of the same field suppresses it (`nonzero`).
4. Binary and two-level status was still decided once from the whole
   response. When the whole response was multi-valued, a group whose own
   values were 0/1 (3 zeros among 50) or 1/2 (3 twos) got only a nonzero
   check, and its coefficient revealed a count that the descriptive review of
   the same field restricted to that group suppresses (`zero_valued`,
   `two_level`). The excluded missing count was also unchecked. Rather than
   patch these cases, one helper now applies the descriptive row rule to each
   group's own values, and the model sample checks the missing count. A
   consistency test reviews the same field restricted to each probe group with
   the descriptive review and requires the regression review to suppress
   whenever the descriptive review does.
5. The group rule ran only on the fitted response. A shifted response such as
   `I(y + 1)` moved every zero to a nonzero value, so `I(y + 1) ~ 1` published
   a 3-discharge sum that `y ~ 1` and the descriptive review of `y` suppress,
   and `I(y + 2) ~ group` showed an all-zero group under `zero = "suppress"`.
   Each raw source field of a transformed response is now also checked, and
   the consistency test covers these probes.

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
and missing rows, hospitals and whether the possibly recoded response is
zero/one), `groups` (one row per checked group with its scope, target, check,
level or column value, response split, raw source field when applicable,
count, hospitals and failures) and
`rows` (each declared row's reasons and status). `nis_export_table()` refuses
regression reviews.

## Limitations

For the fitted response and each raw source field, the group rule checks the
same splits as a descriptive row of that field and no others. For a group with
three or more distinct values, only its nonzero rows are checked: a small count
of one particular value, or extreme response values, can still be revealed, as
for a descriptive mean. A response built from several source fields, such as
`I(y1 + y2)`, checks each field separately, not their combinations.

The bounded checks do not address differencing across separately fitted models
or tables, weights that are themselves disclosive, offsets, continuous-predictor
extremes, or information recoverable from covariance matrices beyond the
published standard errors. Numeric predictors with three or more distinct
values are never crossed, so an interaction with one can expose a cell. For
example, in `event ~ group * x` with `x` in {0, 1, 2}, if group A has only
`x = 0` (3 rows) and `x = 1` (50 rows), the fit is saturated within A and its
intercept recovers the 3-row cell, while every checked group passes. Joint
cells of additively combined predictors are checked (item 4), but other
coefficients remain model-based combinations of groups that are not all
enumerated. The missing-outcome count alone is not checked when other model
fields are also missing; only the combined excluded count is. The retained
fitted model frame, model matrix, sample counts (`excluded_missing` and
`supplied`), the provenance `modeled_scale` and `response_fields`, and the
retained design variables used for raw source-field checks are trusted: they must match the table's
coefficients, but a deliberately forged internal frame or sample count is not
recomputed from the retained design and is not detected. A
domain or complete-case exclusion that removes a declared factor level
entirely leaves it out of the fitted levels, so it is not checked, and its
absence from the table is visible to a reader who knows the declared levels.
Groups other than the model sample are checked only among the included
analysis rows; missing counts within groups are not checked. The procedure is
conservative within these checks, not minimal, and not a disclosure
certification. Saad and Ali must review the policy and any applicable
agreement before publication.

## Acceptance cases

Verification uses invented data, an independent hand-counted reference for every
checked group and the installed public API. Cover: gaussian and binomial fits;
the equal-weight one-binary-predictor logistic case with each of the four cells
just inside and outside the range; a small reference level and a small
non-reference level; zero-count fitted levels under both zero policies; a
factor-by-continuous interaction; factor-by-factor and 0/1-by-0/1
interactions with a small reference cell; a small non-reference cell only; a
three-way interaction; factor by logical and factor by a non-0/1 two-valued
numeric predictor; an additive model saturated by an empty cell; a 1/2-coded
response matching its 0/1 coding; a three-valued response with a small
nonzero group under Gaussian and quasipoisson fits; a 0/1 or 1/2 group inside a
multi-valued response (Gaussian and quasipoisson) and a 0/1 joint cell inside
one; a sparse `y ~ 1` response; three missing outcomes; a shifted `I(y + 1)`
response, alone and by group, and an all-zero raw group behind `I(y + 2)`
under `zero = "suppress"`; a consistency test that
the regression review suppresses whenever the descriptive review of the same
field restricted to the same group does; a 0/1 response with one fractional
value; a strictly positive response that stays shown; a joint cell failing
only on hospitals; an empty interaction cell, an all-zero indicator and an
all-one indicator under both zero policies; a crossing over 10000 cells
refused; a count of exactly one; outcome and predictor missingness that
excludes a whole hospital; a two-valued non-0/1 column; a continuous column
with few nonzero values; minimum hospitals for model, column and factor groups;
model-level failure suppressing every row; repeated and reordered terms;
domains and an average annual pool with reused hospital identifiers; logical
predictors; aliased coefficients; nonempty margins refused; altered table
values, declarations or class refused; unchanged caller objects; unchanged
descriptive reviews; and continued export refusal. Extend the installed smoke
and the tables feature recipe.
