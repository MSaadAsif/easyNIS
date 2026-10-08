# Experimental transformed formulas and exposure offsets

This bounded NIS-016/034 continuation extends the existing explicit model
contract with row-wise numeric formula expressions. It does not infer units,
approve distributions or provide automatic effect back-transformation.

Gaussian outcomes may use arithmetic and `log()`, `log1p()`, `sqrt()`, `abs()`
or `I()`. Predictors may use the same expressions. Formula fields must be
retained numeric/logical vectors or explicit factors as before; outcome source
fields cannot be factors. Arithmetic operators are `+`, `-`, `*`, `/`, `^` and
parentheses. Ordinary formula interactions retain native R meanings; use
`I(x^2)` to request the numeric square. Sample-dependent transformations such
as `scale()` or `poly()`, caller functions, namespaces, indexing, dot expansion
and global variables remain refused. Allowed functions resolve in a fixed
base/statistics environment rather than the caller's formula environment.
Fitting rebuilds a plain formula from the checked response and predictor
expressions, discarding supplied terms metadata such as alternate `predvars`.

Quasibinomial and quasipoisson outcomes remain named zero/one or nonnegative
vectors. A transformed Gaussian outcome is reported by its exact expression
and raw source field names. Coefficients and inference stay on that modeled
scale. Exponentiating a coefficient for `log1p(y)` is neither an odds ratio nor
an arithmetic-mean difference; this increment performs no exponentiation.
User-supplied precomputed transformations still require their own provenance.

The only offset form is `offset(log(exposure))` in a quasipoisson model, with
one retained named numeric exposure vector and strictly positive observed
values. Multiple offset terms are refused. The log exposure is part of the
linear predictor with coefficient fixed at one. Exposure units, clinical
interpretation and any risk/rate effect claim remain caller declarations and
later contracts. Raw exposure and native design weights remain unchanged.

Missing counts use every raw formula field, including exposure. NA and NaN
retain the declared complete-case policy. Formula evaluation must produce
single numeric/logical/factor columns and finite observed terms. Nonfinite
expressions or newly missing transformed values from complete raw inputs are
refused, including log zero/negative values, invalid square roots, division by
zero and overflow. Invalid observed exposure is refused even if another field
is missing. Complete-case selection subsets the original native design.
Allowed expressions are row-wise, so evaluating them again on included rows
cannot silently change a centering basis or quantile cutpoint.

Provenance records the exact response expression, response source fields,
whether the modeled outcome is transformed, and any exposure field/expression.
Native formulas, offsets, fits, raw analysis columns, factor matrices, warning
messages and full-design/domain accounting remain available. Native prediction
uses the same fixed allowed-function environment.

The mechanics follow the official R [GLM](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/glm.html)
and [model-frame](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/model.frame.html)
documentation. These sources define native evaluation and offsets; they do not
establish scientific suitability for NIS outcomes.

Acceptance cases include direct native and independent score-sandwich
references for log1p Gaussian outcomes, squared/log predictors, and Poisson
exposure offsets. Domain hospitals absent after outcome/exposure exclusions,
pooled reused IDs, raw missing counts, factor coding, native prediction,
caller-function shadowing, supplied terms metadata and every rejection above must be exercised.
Scientific approval, annual support and interpreted effects remain pending.
