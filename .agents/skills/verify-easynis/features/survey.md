# Experimental survey design and domains

The installed public workflow constructs a complete invented-year design and
then subsets logical domains. It checks an independently calculated weighted
total and variance with hospitals absent from the domain.

Run `./tools/verify.ps1 -Doctor`, which requires the optional survey package for
development verification, then `./tools/verify.ps1`. The installed workflow
exercises `nis_survey_design()` and `nis_domain()` for every invented 2017-2022
label. Inspect `installed-workflow.log`, package test results and source check.
Offline help examples construct a native design and domain.

The package suite compares direct native reference designs and independent
arithmetic, including domain mean linearization, missing outcomes, singleton
rejection, raw/exact identifiers, BIGINT weights, unsafe probabilities, logical
missingness and nondefault option preservation. It does not certify annual
conversions or promote scientific approval. Read `docs/SURVEY.md` for the
method contract, inference limits and unbenchmarked eager-memory behavior.

The installed workflow also pools all six complete invented-year designs after
their DuckDB sessions close. It verifies 24 separate year/hospital PSUs and
12 year/strata, plus independently calculated combined and average annual
domain totals and variances. The package suite adds direct native references
with reused identifiers and varying annual weights, and rejects duplicate years,
prior domains and incompatible fields/levels. Read `docs/POOLING.md` for the
explicit estimand/divisor contract and remaining scientific gates.

The installed workflow now exercises `nis_estimate()` for scalar domain totals,
means and logical proportions for every invented year, with explicit missingness,
unadjusted WR variance, confidence and interval degrees of freedom. It asserts
numeric estimates, independent SEs, t/normal interval bounds, raw sample counts
and retained native results. The pooled path checks combined total 264/SE
sqrt(5808), average annual total 44/SE sqrt(5808)/6 and weighted pooled
proportion 0.5/SE sqrt(972)/216. Inspect the scalar reference messages in the
installed log as well as the source check and package results.

Package cases calculate independent WR hospital contributions across the full
sample. They include sparse domains, unequal hospital counts, whole hospitals
and strata without observed outcomes, reused annual IDs, negative sentinels,
safe/unsafe BIGINT outcomes, zero results, t/normal intervals, raw/provenance
preservation and rejection of incompatible current options without mutation.
Read `docs/ESTIMATES.md` for current-option requirements, separate native versus
caller-selected degrees of freedom, sample accounting and approval limits.

The installed workflow calls `nis_model()` for Gaussian identity, quasibinomial
logit and quasipoisson log intercept fits for every invented year. Independent
weighted-mean and hospital WR arithmetic, followed by link derivatives, checks
coefficients, SEs, t intervals and complete-case accounting. Read `docs/MODELS.md`.
The source suite adds multivariable native/independent score-sandwich references,
factor interactions/contrast matrices, aliased terms, zero SEs, pooled reused IDs,
missing hospitals and explicit rejection paths. These results do not promote
annual support, interpreted effects or scientific approval.

Installed calls also exercise `log1p(LOS)` Gaussian means and a quasipoisson
log-exposure offset for every invented year. Independent transformed means,
weighted outcome/exposure ratios and hospital-score WR variances check numeric
coefficients/SEs, modeled-scale metadata, offsets and raw columns. Package cases
add squared/log predictors, source-field missing counts, pooled reused IDs,
prediction with the fixed formula environment and invalid expression/exposure
rejection. Read `docs/MODEL-FORMULAS.md` for the bounded syntax and scale contract.

The installed workflow calls `nis_model_contrast()` on a Gaussian slope fit for
each invented year. Independent weighted least-squares coefficients and hospital
WR sandwich covariance check profile-difference estimates, SEs, t intervals and
link tests. Inspect the model contrast reference messages in the installed log.
The installed model workflow also checks per-level factor-support rows and
empty declared levels for every invented year. A pooled average-annual-total
fit checks divisor-preserved analysis weights and distinct year-specific
hospital counts after pooling reused hospital IDs. The package model suite
independently counts support after domain and whole-hospital missingness, checks
logical missing values and `I()` factor/logical terms, verifies contrast and
covariance preservation, and guards against expression-label collisions.
The focused source command is `testthat::test_local(filter = "model")`; shared
invented fixture and score-sandwich helpers are in `helper-model.R`.
The contrast suite includes interactions, finite/infinite df, reverse contrasts,
pooled reused IDs, missing hospitals, explicit odds/mean/rate ratios, alias zeros
and refusal, transformed outcome labels, offset semantics, diagnostics and
zero/nonfinite numerical boundaries. Read `docs/MODEL-CONTRASTS.md`. Annual
support and scientific approval remain pending.
