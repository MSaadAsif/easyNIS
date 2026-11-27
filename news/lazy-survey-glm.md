## New features

- Fit additive Gaussian identity, binomial and quasibinomial logit, or Poisson
  and quasipoisson log `svyglm()` models on a lazy `nis_survey()` design. DuckDB
  computes the weighted model sums and Taylor PSU scores, and the fit supports
  Wald inference, broom, and `gtsummary::tbl_regression()`.
