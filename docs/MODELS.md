# Experimental survey GLMs

`nis_model(design, formula, family, missing, df, confidence, variance)`
fits a native survey regression after explicit complete-case selection on an
existing single-year, pooled or logical-domain design. This is the first
invented-input increment for NIS-016, with numeric inference checks from
NIS-017. Annual validation and author scientific approval remain pending.

Choose `family = "gaussian"`, `"quasibinomial"` or `"quasipoisson"`,
`missing = "fail"` or `"exclude"`, and `variance = "wr_unadjusted"`.
Supply positive numeric `df` or `Inf` and numeric confidence between zero and
one. The Gaussian identity link permits finite negative outcomes, including
raw sentinels. The logistic logit link requires numeric or logical zero/one
outcomes. The Poisson log link requires finite nonnegative outcomes and permits
fractional values. Neither family nor missing-sentinel meanings are inferred
from a field name. This wrapper does not exponentiate coefficients or infer
odds, risk, rate or causal interpretations.

## Formula and analysis population

The formula has one named outcome and ordinary named predictor terms,
interactions and intercept declarations. Named fields may contain spaces or
punctuation when quoted with R backticks. All formula fields must be retained
in the supplied design. Native internal names `.survey.prob.weights`,
`(weights)` and `(offset)` are refused as model fields because native fitting
overwrites or specially interprets them.
Numeric/logical vectors and explicit factor predictors
are accepted. Character, BIGINT, other classed vectors and matrix fields are
refused. Declare conversions and factors explicitly before modeling; native
design edits remain the caller's responsibility and are not authenticated by
the constructor's earlier provenance. Transformations, offsets, dot expansion,
grouped responses and custom families are refused in this increment. Their
modeled-scale, exposure and missingness contracts remain backlog work.

NA and NaN in any formula field are missing. Exclusion subsets the existing
native design, preserving original hospital information and zero contributions
from absent hospitals. The full design is never reconstructed from complete
cases. Infinite fields and invalid family outcomes are rejected even on rows
missing another predictor. Empty analyses, nonfinite weighted denominators,
nonfinite estimable coefficients/covariances and nonfinite interval bounds are
refused. Unrelated retained fields do not cause complete-case exclusions.

`sample` reports supplied domain rows, included complete cases, the union count
of exclusions and named per-field missing counts. Per-field counts overlap and
must not be summed to obtain excluded rows. Weighted denominator, original
population df, supplied-domain df, complete-case-design df and native residual
df are distinct. The constructor's full provenance and domain history remain
available. Raw columns, native analysis weights and caller options remain
unchanged; the input object is not modified.

## Native fit, contrasts and inference

`native` is the unchanged `survey::svyglm` fit. Native fitting weights rescale
to sum to analysis rows, independent of the design's pooling divisor. Gaussian
identity, quasibinomial logit and quasipoisson log are constructed internally.
IRLS uses epsilon `1e-10` and at most 50 iterations, recorded in provenance.
`summary` uses the caller's explicit `df.resid`; standard `summary(native)`
still uses survey's native residual-df default. No native df is overwritten.
Finite caller df uses t tests and t Wald intervals; `Inf` uses normal tests
and intervals. Confidence bounds remain on the coefficient's link scale.

`coefficients` retains every coefficient, including aliased terms with NA
inference. Zero estimates and SEs are valid. A zero estimate with zero SE has
the native undefined test statistic/p-value rather than an invented test.
`factors` records fitted levels, explicit contrast matrices, ordered status
and any zero-coded levels. Treatment contrasts identify the reference level;
sum and polynomial contrasts need not have one. Matrices are fixed when
fitting so later contrast-option changes cannot alter the recorded coding.
Logical predictors follow native factor coding with levels FALSE and TRUE;
their matrices are fixed and reported without changing raw logical columns.
Logical responses remain zero/one outcomes and are not factor predictors.
One-level analysis factors follow native rejection, without silently dropping
the formula term. Distinct warning messages from frame preparation, fitting
and summary are captured in `diagnostics`, along with rank,
aliased terms, convergence and boundary status. Finite nonconverged fits can
return for inspection; they are not certified. Automated separation/sparsity
diagnosis and interpreted effects remain NIS-017 work.

The declared variance requires current `survey.lonely.psu = "fail"` and
`survey.adjust.domain.lonely = FALSE`; incompatible options are refused.
The native behavior and quasi-family/df choices follow the official
[survey GLM documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svyglm.html).
These are explicit experimental choices, not scientific recommendations.

## Reference evidence

Invented tests compare all three families with direct native fits and separate
canonical-link score sandwich calculations. For each original hospital, sum
included weighted scores, assigning zero to excluded discharges. Within each
stratum, form the centered hospital-score cross-product with factor `m/(m-1)`.
Multiply the resulting covariance on each side by the inverse information
matrix. Independent Gaussian calculations use absolute tolerance `1e-10`;
iterative-family covariance/interval comparisons use absolute `1e-7` because
native covariance uses final IRLS working weights, while the separate reference
uses derivatives at final fitted means. Direct matching native fits use
`1e-12`. These small invented cases do not establish a large-data error bound.

Cases include complete hospitals absent through domain or missingness, reused
annual identifiers, unequal annual weights, pooling-divisor invariance,
factor interactions and treatment/sum coding, aliasing, a deliberately extreme
nonconverged fit with retained native warning, zero coefficients/SEs,
quoted fields, raw sentinels and rejection paths. The installed workflow tests
intercept-only fits for all three links against independent weighted means
and hospital WR variances for every invented 2017-2022 label.

No model or annual support state is promoted. Transformed outcomes, exposure
offsets, interpreted effects, broader diagnostics, licensed references and
memory benchmarks still need their separate contracts and evidence.
