# Experimental disclosure review for regression tables

This is the next bounded NIS-019 increment. It extends
`nis_disclosure_review()` to one unchanged `nis_regression_table()` result.
Export of the reviewed regression presentation remains a separate NIS-020
increment; `nis_export_table()` continues to refuse regression reviews until
then. The review assists a human publication check. It does not certify a
manuscript, approve the policy or promote annual support.

## Why counts matter for coefficients

A coefficient table publishes no cell counts, but its numbers can reveal
them. In an unweighted or equal-weight logistic model with one binary
predictor, the intercept and slope give the within-group event proportions,
and model-based standard errors would determine all four predictor-by-outcome
cell counts. The design-based standard errors that easyNIS publishes do not
determine them exactly but can still reveal them. A factor level, reference
level or interaction cell containing a few discharges yields coefficients that
describe those discharges. The review therefore checks bounded unweighted
analysis-sample groups: the model sample; each fitted model-matrix column's
levels, or its nonzero and zero-valued rows; each fitted factor or logical
level; and every cell of the joint crossing of all factor, logical and
two-valued numeric predictors in the model. Each of these groups is also
split by response: into event and nonevent rows for a two-valued response, or
otherwise into its rows with a nonzero response. The caller's explicit policy
applies throughout. It does not check every group a fitted
model implicitly depends on; see the limitations.

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

A response is binary when it is logical, every included value is 0 or 1, or
it has exactly two distinct included values under exact equality, whatever
their coding (1/2, 0/2 or a transformed 0/1 outcome). The event is the value 1
(or `TRUE`) for a logical or zero/one response and otherwise the upper value;
the other value is the nonevent.

Every checked group below is split by response, and each split is itself a
checked group with the same range, zero and hospital policies and the same
consequences as its parent group. For a binary response the splits are the
event and nonevent rows (`<check>_events`, `<check>_nonevents`). Any other
response is checked like a descriptive field: the split is the rows with a
nonzero response (`<check>_response_nonzero`). Its zero-valued complement is
not checked, as in the descriptive review, so a strictly positive outcome is
not suppressed for having no zero values. Other splits of a multi-valued
response are not checked.

1. Model checks. The included count and its hospitals. For a binary response,
   the event and nonevent counts, otherwise the nonzero-response count
   (`response_nonzero`), with their hospitals. Any failure suppresses every
   row (`model:<check>`).
2. Coefficient column checks, using every fitted model-matrix column,
   declared or not:
   - The intercept has no checks of its own. Any other constant column checks
     its nonzero count, and a constant nonzero column also its zero-valued
     count. An all-zero column, such as an empty interaction cell or an
     indicator that is zero for every analysis row, has a zero `nonzero`
     count, and an indicator equal to one on every row has a zero
     `zero_valued` count, so both follow the zero policy.
   - A column with exactly two distinct values checks both level counts
     (`lower_level`, `upper_level`). With a binary response, it also checks the
     four level-by-outcome cells (`lower_level_events`,
     `lower_level_nonevents`, `upper_level_events`, `upper_level_nonevents`).
   - A column with three or more distinct values checks its nonzero count and,
     when present, its zero-valued count (`nonzero`, `zero_valued`).
   Every column group is split by response as described above; the
   two-valued column names show the binary case.
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
4. Joint cells. When the model has two or more factor, logical or
   two-valued numeric predictors, every cell of the full joint crossing of
   all of them is checked, whether they interact or enter additively. Cells
   use fitted factor levels and the observed two values, and include the
   reference cell and empty cells, with cell-by-response cells for a binary
   response (`cell`, `cell_events`, `cell_nonevents`). A failing cell
   suppresses the rows of every term containing any crossed predictor and the
   lower-order terms within them, including the intercept
   (`cross:<variables>`). A crossing of more than 10000 cells is refused
   rather than reviewed. Numeric predictors with three or more distinct values
   are not crossed.
5. Repeated terms. Rows declaring the same coefficient name share one fitted
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
- The response is the fitted model response, so a transformed response
  follows the binary rule above on its transformed values: `log1p(y)` with `y`
  in {0, 1} has two distinct values and is binary.

Independent review of the first implementation added these checks:

- Interaction cells are crossed (item 4). In `event ~ group * sex` the
  intercept is the logit of the reference cell, so a 3-row reference cell was
  disclosed although every marginal level and column passed. Two-valued
  numeric predictors are crossed as well, because a 0/1 interaction has the
  same structure.
- Only the intercept is exempt among constant columns (item 2), so an aliased
  all-zero row no longer reveals an empty group under `zero = "suppress"`.
- A table that matches its retained model, but whose retained fit,
  coefficients or factors are internally inconsistent, is refused with a
  separate message from an altered table.

A second review found further unchecked cells. Rather than add cases one at a
time, these broader rules replace them:

- Every two-valued response is binary (see above). A Gaussian `y ~ group`
  with `y` coded 1/2 and three upper values in group A revealed a 3-count cell
  that the same data coded 0/1 suppressed.
- All factor, logical and two-valued numeric predictors are crossed jointly
  (item 4), not only those sharing an interaction term. An empty B/M cell made
  the additive `event ~ group + sex` saturated, so its intercept was exactly
  the logit of a 3-row A/F cell. Joint crossing suppresses more than
  necessary in additive models with many categorical predictors, and empty
  joint cells under `zero = "suppress"` hide every crossed term; both are
  accepted as conservative. The 10000-cell refusal bounds the work.
- A constant nonzero column other than the intercept checks its zero-valued
  count, mirroring the all-zero case.

A third review found that a response with three or more distinct values had
no response checks at all: in `y ~ group` with group A holding three `y = 1`
values among zeros and group B adding 2s, the intercept recovered the 3-row
total, and `y ~ 1` with 3 of 100 nonzero values was shown although the
descriptive review of the same field suppresses it (`nonzero`). One fractional
value also turned a 0/1 response non-binary and disabled its checks. Every
group of a non-binary response now checks its nonzero-response rows, and every
column group, not only two-valued columns, is split by response.

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

For a multi-valued response only the nonzero-response rows of each group are
checked. A small count of any particular nonzero value, a small zero-valued
group within a group, or extreme response values can still be revealed.

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
enumerated. The retained fitted model frame and model matrix are trusted: they
must match the table's coefficients, but a deliberately forged internal frame
is not compared with the retained design variables and is not detected. A domain or
complete-case exclusion that removes a declared factor level entirely leaves it
out of the fitted levels, so it is not checked, and its absence from the table
is visible to a reader who knows the declared levels. Groups are checked only
among the included analysis rows. The procedure is conservative within these checks,
not minimal, and not a disclosure certification. Saad and Ali must review the
policy and any applicable agreement before publication.

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
nonzero group under Gaussian and quasipoisson fits; a sparse `y ~ 1` response
also suppressed by the descriptive review; a 0/1 response with one fractional
value; a strictly positive response that stays shown; a joint cell failing
only on hospitals; an empty interaction cell, an all-zero
indicator and an all-one indicator under both zero policies; a crossing over
10000 cells refused; a count of exactly one; outcome
and predictor missingness that excludes a whole hospital; a two-valued non-0/1
column; a continuous
column with few nonzero values; minimum hospitals for model, column and factor
groups; model-level failure suppressing every row; repeated and reordered terms;
domains and an average annual pool with reused hospital identifiers; logical
predictors; aliased coefficients; nonempty margins refused; altered table
values, declarations or class refused; unchanged caller objects; unchanged
descriptive reviews; and continued export refusal. Extend the installed smoke
and the tables feature recipe.
