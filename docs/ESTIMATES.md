# Experimental scalar survey inference

`nis_estimate(design, field, statistic, missing, df, confidence, variance)`
returns one numeric estimate, SE and Wald interval from an experimental
single-year, pooled or domain design. This advances the invented-input portion
of NIS-015. It does not approve scientific choices or promote annual support.

Choose `statistic = "total"`, `"mean"` or `"proportion"`,
`missing = "fail"` or `"exclude"`, and `variance = "wr_unadjusted"`.
Supply a positive numeric `df` or `Inf`, and numeric `confidence` strictly
between zero and one. There are no defaults for these inference choices.
Finite degrees of freedom use Student's t; `Inf` uses the normal quantile.
The interval is estimate plus/minus the critical value times the SE. Bounds
are not clipped, including for proportions, and can exceed outcome bounds.

The retained outcome must be a plain numeric or logical vector. Proportions
require every observed value to be zero or one. Factors and string-coded
outcomes require an explicit reviewed transformation before construction.
BIGINT outcomes convert through exact character values only below absolute
2^53. Raw columns in the input and returned analysis design keep their types.
Numeric sentinels, including negative values, keep their raw meanings. Infinite
outcomes are refused. NA and NaN are missing. Exclusion uses native design
subsetting, preserving full-population PSU sizes and zero contributions from
absent hospitals. Empty analyses, nonfinite results and nonfinite analysis
weight denominators are refused; zero estimates and zero SEs are valid.

## Native results and accounting

The API passes a one-column numeric matrix to `survey::svytotal()` or
`survey::svymean()`. Logical proportions become numeric zero/one outcomes,
giving one scalar rather than separate FALSE and TRUE estimates. Exact field
names are matrix column names, without formula parsing. The unchanged native
`svystat` is in `native`; `design` contains the outcome-subset native design.

`sample` separates supplied domain rows, included observations and excluded
missing outcomes. It also reports the included weighted denominator, native
domain degrees of freedom before outcome exclusion, native analysis degrees
of freedom after exclusion, and original full-population degrees of freedom.
`df` records the caller's separate interval choice, even when native domain
degrees of freedom are zero. This is a caller declaration, not a recommendation
or validation of that choice. Provenance retains the constructor's entire
design provenance, full-population accounting and sequential domain history,
the current survey options/version and all inference declarations.
`analysis_ready` remains `FALSE`.

For pooled designs, a total carries the constructor's `combined_total` or
`average_annual_total` intent; total estimation is refused for
`pooled_proportion` intent. Means/proportions carry `weighted_pooled_mean` or
`weighted_pooled_proportion`, regardless of the total-weight divisor. They are
weighted across included discharges, not arithmetic averages of annual means
or proportions. Included years and divisor remain in design provenance.

## Options and reference evidence

The declared unadjusted hospital WR policy requires current
`survey.lonely.psu = "fail"` and `survey.adjust.domain.lonely = FALSE`.
Incompatible options cause an error and are not changed. Current options may
differ from construction-time options, so both snapshots remain available.
`survey.ultimate.cluster` does not affect this single-stage design without an
FPC; either value is accepted and recorded. The R and Rcpp variance paths are
both tested. Replicate-weight options do not control this design's variance.

These choices follow the native [summary documentation](https://r-survey.r-forge.r-project.org/survey/html/surveysummary.html),
which accepts a vector or matrix, and [survey option documentation](https://r-survey.r-forge.r-project.org/survey/html/surveyoptions.html).
The installed survey 4.5 methods were also inspected for matrix conversion,
WR variance calls and native subsetting. These sources establish API behavior,
not annual correctness or scientific approval.

Independent tests calculate WR variances by summing weighted outcome or mean
linearization contributions per original hospital, then summing each stratum's
`m/(m-1) * sum((hospital_contribution - stratum_mean)^2)`. Domain and missing
outcome exclusions give zero contributions rather than deleting original PSUs.
Cases include unequal hospital counts, absent hospitals and an absent stratum,
one-observation domains, pooled reused IDs with varying annual weights, raw
negative sentinels, safe and unsafe BIGINT values, zero results, and explicit
t/normal intervals. Small deterministic double cases use tolerance 1e-12.
The installed six-year workflow separately verifies total 264 with variance
5808, average annual total 44 with variance 5808/36, weighted LOS mean 22/9,
and pooled domain proportion 0.5 with variance 972/216^2.

Author review of inference choices, official annual/conversion contracts,
licensed references, model behavior and disclosure safeguards remain pending.
