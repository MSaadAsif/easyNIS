# Experimental model profile contrasts

`nis_model_contrast(model, contrast, interpretation)` applies finite named
coefficient weights to an existing `nis_model`. The caller supplies weights
that describe the intended difference between model-matrix profiles. The
function matches exact coefficient names, including factor and interaction
names. It does not build profiles, verify that weights describe attainable
profiles, infer units, or establish scientific meaning.

Weights must be a nonempty plain numeric vector with unique, nonempty names.
Omitted coefficients have weight zero. Unknown names, nonfinite values,
all-zero weights and nonzero aliased weights are refused. Zero weights on
aliases are allowed. Every interpretation requires a zero intercept weight.
For `y ~ x * group`, a change from `x = 0, group = 0` to `x = 2, group = 1`
uses `c(x = 2, group = 1, "x:group" = 2)` when `group` is numeric zero/one.
A factor uses its fitted coefficient names and recorded coding instead.

## Explicit interpretation and scales

| Interpretation | Permitted model | Meaning for declared profiles |
|---|---|---|
| `link_difference` | Every supported family | Difference in the fitted covariate linear predictor on the modeled link scale |
| `mean_difference` | Gaussian with a named outcome | Difference in conditional modeled arithmetic means |
| `odds_ratio` | Quasibinomial logit | Ratio of conditional modeled odds |
| `mean_ratio` | Quasipoisson log without an offset | Ratio of conditional modeled means |
| `rate_ratio` | Quasipoisson log with a log-exposure offset | Ratio of conditional modeled expected outcome per exposure |

Transformed Gaussian outcomes require `link_difference`. The exact outcome
expression and source fields remain in `scales` and provenance. For example,
a difference in modeled `log1p(y)` means is not an arithmetic-mean difference
on the raw `y` scale. A named field that the caller already transformed cannot
be detected; the caller remains responsible for that field's definition.

These meanings follow algebra from the identity, logit and log links defined
in the official [R family documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/family.html).
If `eta = log(p / (1 - p))`, `exp(eta_B - eta_A)` is an odds ratio. If
`eta = log(mu)`, exponentiating its difference gives `mu_B / mu_A`. With
`log(mu) = X beta + log(exposure)`, `exp(X beta)` is expected outcome per
exposure. The coefficient contrast excludes the fixed log-exposure difference.
It compares these modeled rates even when the declared profiles have unequal
exposures. To compare outcome means at unequal exposures would also require
the exposure ratio, which this API does not calculate. A link contrast also
excludes the offset difference; `scales$offset_difference_included` is FALSE.

Interpreted mean differences and ratios require a converged, nonboundary fit.
Link differences permit inspection of finite nonconverged or boundary fits and
retain their warnings and diagnostics. Passing that guard does not establish
absence of separation, adequate sample size, or scientific suitability.
An odds ratio is not a risk ratio. These are conditional model contrasts;
population standardization, marginal effects and causal claims are unsupported.

## Covariance and inference

With weights `c`, fitted coefficients `b` and full coefficient covariance `V`,
the link estimate is `c' b` and variance is `c' V c`. Active coefficients use
every covariance cross-term, including interactions. Zero-weight terms are
removed before multiplication so aliases cannot introduce NA. A nonfinite
estimate or covariance calculation, negative variance, nonfinite SE or interval
bound is refused. Small negative calculated variances are refused rather than
silently truncated. These rejection guards and the intercept restriction are
explicit easyNIS policies. Matching named weights, omitted zero weights and
delta-method uncertainty for nonlinear functions follow the official
[survey contrast documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svycontrast.html).

The original model's explicit `df` and `confidence` determine Wald inference.
Finite df uses a t distribution; `Inf` uses a normal distribution. Tests use
`link_estimate / link_se` against link null zero. `statistic`, `p_value`,
`test_scale = "link"` and `test_null = 0` report that test. Difference results
have effect null zero; ratios have effect null one. The native fit's residual
df remains unchanged and is still available in sample accounting.

Differences report the link estimate, SE and bounds directly. Ratios report
`exp(link_estimate)` and exponentiated link Wald bounds. `link_se` always
means link-scale uncertainty. `effect_se` is the same SE for differences and
`exp(link_estimate) * link_se` for ratios, a delta-method SE. The ratio bounds
come from transforming the link interval, not from a symmetric interval using
`effect_se`. Nonfinite ratio estimates, bounds or SEs and estimates/bounds that
underflow to zero are refused.

Zero variance is valid. A zero estimate with zero SE keeps the undefined NaN
statistic and p-value. A nonzero link estimate with zero SE has an infinite
signed statistic and p-value zero. Estimates, SEs and bounds must remain finite
even though those degenerate test statistics can be undefined or infinite.

The `nis_model_contrast` result retains the complete original `model`, sample,
factor matrices, diagnostics, supplied and expanded weights, interpretation,
response/exposure scales and complete model provenance. It changes neither
the model nor its native fit, raw columns, weights, options or residual df.
Its `analysis_ready` flag remains FALSE.

## Reference evidence and limits

Invented public tests compare interaction contrasts to separate model-matrix
calculations and independent hospital score sandwiches. Those calculations
retain zero contributions from excluded hospitals across domain/missingness
selection and pooled reused year/hospital identifiers. Gaussian references use
absolute tolerance `1e-10`; iterative-family references use `1e-7`, consistent
with the existing final-IRLS versus fitted-mean covariance distinction.
Direct native `svycontrast` is an additional Gaussian comparison.

Cases exercise finite/infinite df, reverse differences and reciprocal ratios,
factor coding, alias zero/rejection, transformed-response labels, offset versus
nonoffset interpretations, declaration failures, nonconvergence, boundary
guards, zero variance and numerical overflow/underflow. Exact arithmetic guard
cases explicitly replace coefficient/covariance values in a real fit; those
are numerical boundary tests, not evidence about native fitting behavior.
Installed public workflows fit a slope model and compare contrast estimates,
SEs and intervals to independent weighted least-squares and hospital WR
references for every invented 2017-2022 label.

This is an experimental NIS-017 increment. It does not promote annual support
or scientific approval. Broader separation/sparsity diagnosis, marginal effects,
licensed references and author review remain pending.
