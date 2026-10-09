# Experimental factor support counts

`nis_model()` reports `diagnostics$factor_support` for each factor or logical
predictor in its fitted model frame. A named list entry contains a data frame
with `level`, `supplied_rows`, `analysis_rows`, `analysis_weight`, and
`analysis_hospitals` columns. The supplied side covers the caller's complete
supplied domain before complete-case selection; the analysis side covers the
retained model design.

For a predictor that is a raw named factor, rows are reported in its declared
factor-level order, including declared levels with no supplied observations or
no complete cases. Logical predictors use FALSE then TRUE. Other factor or
logical expressions report levels available from their evaluated supplied
model-frame value. The native model-frame operation can discard unused levels
for expressions, so this bounded API does not reconstruct declared levels
through a general expression parser.
An actual NA factor level is an observed category and appears as an NA value in
`level`; the literal string `"NA"` is a separate category. A genuinely missing
factor code is excluded from raw named-factor level counts and remains in
missingness accounting. Supplied counts for named raw factors use their
integer codes, because R's model-frame operation can map a true missing code
onto an explicitly declared NA level. For a factor expression such as
`I(group)`, supplied counts follow its evaluated full model-frame values, so
that same recoding may count the source missing row in the expression's NA
level. The source missing count remains in `sample$missing_by_field`, and the
existing raw complete-case rule still excludes that row from analysis counts.
Analysis counts use the retained complete-case factor codes.
Formula terms that produce duplicate model-frame column names are refused
before support counting. A raw field named `I(group)` can coexist with the
expression `I(group)` in the design, as long as only one is included in the
formula; including both requires renaming the field or reformulating.

`analysis_weight` sums the retained design's native analysis weights by level,
preserving any pooling divisor. `analysis_hospitals` counts distinct values of
the first native nested cluster identifier among retained rows at that level.
This keeps identical hospital IDs from different pooled years distinct.
True missing codes in the counted vector do not contribute to a level row.
Source-field missingness remains in `sample$missing_by_field` and the existing
supplied/included/excluded sample counts, including expression recoding cases
described above.

The diagnostics are descriptive support counts. They do not apply a threshold,
diagnose separation or convergence, or certify a fit scientifically. They do
not change raw fields, model terms, factor coding, native fitting, covariance,
analysis weights, or caller options.

Invented tests independently count levels, rows, raw design weights, and
hospital identifiers for complete-case/domain analyses, declared unused
levels, logical values with missingness, pooled reused hospital IDs, and pooled
weight scaling. They compare the fitted native object and coding with a
reference fit. An installed-package smoke case covers the public result shape
and pooled hospital counts. No source data or annual support is added.
