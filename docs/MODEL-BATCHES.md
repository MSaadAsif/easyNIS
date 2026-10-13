# Experimental outcome-model batches

`nis_models(design, outcomes, predictors, missing, df, confidence, variance)`
fits several named outcomes with one shared predictor declaration. This bounded
NIS-016/021 usability increment removes repeated model formulas while retaining
the existing [model contract](MODELS.md). It adds no new inference method.

```r
families <- c(binary = "quasibinomial", stay = "gaussian", count = "quasipoisson")
batch <- nis_models(design, families, ~ exposure + age,
  missing = "exclude", df = 6, confidence = 0.95, variance = "wr_unadjusted")
batch$sample
batch$models$binary$coefficients
```

Families are explicitly mapped to exact retained outcome names in a plain named
character vector. Names must be unique and nonblank; declaration order is kept.
The shared predictor formula is one-sided, including `~ 1` for intercept-only
models. Interactions, supported row-wise predictor expressions and the existing
Poisson offset restriction follow `nis_model()`. A shared offset therefore
cannot be used with mixed Gaussian/logistic families. Named fields containing
spaces or punctuation are treated literally, never parsed as R code.
Transforms of responses and different predictor sets use separate `nis_model()`
calls; the batch does not guess transformations from names or units.

Each model uses the same supplied full-population, pooled or domain design and
independently applies the declared complete-case policy to its required fields.
It does not take complete cases across all outcomes. The `sample` data frame
lists supplied, included and excluded-missing discharge counts and the weighted
denominator by outcome/family. Samples can differ; counts across outcomes overlap
and must not be summed. Native residual/analysis df, warning and convergence
diagnostics, factor coding, coefficients and full provenance remain in each
complete `nis_model` object under `models`. No result is rounded or exponentiated.

Shared declarations, pointwise inference, no multiplicity correction, unreviewed
disclosure and `analysis_ready = FALSE` are explicit in batch provenance.
Warnings are retained per model rather than collapsed into a claim that a batch
succeeded scientifically. A finite nonconverged fit has the existing model's
behavior and remains inspectable with its diagnostics. Annual validation and
scientific approval are unchanged; model results remain internal and cannot be
exported through descriptive-table disclosure review or rendering.

Malformed declarations fail before fitting. If a model fails, the call returns
no partial batch; its `nis_models_error` condition identifies the exact outcome
and retains the original error in `parent`. Earlier fits are not exposed in the
error. The supplied design, raw columns, formula object, options and existing
results are unchanged. Formula environments/terms metadata are discarded, and
existing field/type/function restrictions remain enforced by `nis_model()`.

Acceptance evidence must cover mixed families and outcome-specific missingness
on full, domain and pooled designs; independent score-sandwich references;
exact fit/covariance/accounting parity with separate calls; quoted fields;
caller-state preservation; warning/alias retention; failed later outcomes;
malformed declarations; unsafe formulas and option guards. Installed public
calls must exercise all three links for invented 2017–2022 labels. This does
not validate clinical variables, weight aliases, prefiltered input or licensed
annual workflows.
