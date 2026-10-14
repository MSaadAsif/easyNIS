# Experimental single-year survey preparation

`nis_survey_design()` constructs a native `survey` design from all supplied
discharges before `nis_domain()` selects a logical domain. This advances the
invented-input portion of NIS-013. It authenticates no annual conversion or
scientific choice and does not promote the installed capability matrix.

## Required declarations

Supply `full_population = TRUE`, `method = "hospital_wr"` and
`singleton = "fail"`. The population declaration is unverified. A prefiltered
source cannot recover the omitted hospitals by making this declaration. The
prototype supports one supplied year, HOSP_NIS hospital clusters, NIS_STRATUM
strata and DISCWT weights, with replacement and no FPC or scaling. Historical
weights and alternative singleton policies remain unsupported. Experimental
pooling is described in [POOLING.md](POOLING.md), and explicit scalar inference
in [ESTIMATES.md](ESTIMATES.md).

Identifiers must pass structural validation and exact collection. A hospital
mapped to multiple strata is refused. Weights must be finite and positive;
integer64 weights are converted through exact strings to doubles below 2^53.
Larger BIGINT weights are refused. Tiny weights whose reciprocals overflow are
also refused. Raw collected columns remain unchanged.

Hospital/stratum validation retains each hospital's first observed mapping and
checks every discharge against it with exact character matching. It rejects a
conflict wherever it occurs, including after long runs of repeated hospitals.
This avoids row-wise data-frame deduplication across the full discharge set.
Native survey construction, row order, raw identifiers, population accounting
and statistical policies remain unchanged.

### Reproduce preparation measurements

The developer tool `tools/benchmark-survey-preparation.R` creates a fixed,
entirely invented seven-million-row input with four shards. It measures the
actual eager preparation and checks row, weight, hospital, stratum and df
accounting. It refuses existing fixture/output destinations and writes success
only after all assertions pass. Run it in fresh R processes:

```text
Rscript tools/benchmark-survey-preparation.R prepare <baseline-library> .audit/preparation-fixture
Rscript tools/benchmark-survey-preparation.R run <baseline-library> .audit/preparation-fixture .audit/baseline-1
Rscript tools/benchmark-survey-preparation.R run <candidate-library> .audit/preparation-fixture .audit/candidate-1
```

Replace the library placeholders with installed package-library directories.
Quote paths containing spaces.
Alternate baseline/candidate at least five times, changing output suffixes;
keep the same fixture, two-GB DuckDB bound and four threads. Retain exit status,
errors and success artifacts, compare medians/ranges, and inspect the saved
constructor and session versions. Profile separately from measured runs.
Generation is outside the timed stages. This narrow invented workload does not
measure full analysis/export, system RAM/disk peaks or licensed-year readiness;
object sizes are not peak process memory. No supported memory envelope follows.
Failed runs retain their directories for inspection; choose new destinations
when retrying rather than overwriting the evidence.

On one Windows workstation (16 logical processors, approximately 40 GB RAM),
five alternating fresh-process runs per implementation measured a native
preparation median of 27.04 seconds before and 22.03 seconds after this change.
Ranges were 26.27–27.28 and 21.81–23.16 seconds, with zero failures. Both used the
same fixed invented input, R 4.6.1, survey 4.5, DuckDB 1.5.5 and the configuration
above. Pre-run system CPU activity ranged from 3% to 29%; this was a desktop
measurement rather than an isolated machine. Separate profiling attributed the
removed work to row-wise mapping deduplication; native survey construction
dominates the remaining sampled work. This measures narrow preparation only,
with full analysis/export and licensed six-year validation still outstanding.

Provide explicit analysis `columns`. Structural fields are included, while
unrequested wide code columns are omitted from design memory. Collection is
eager and has no verified large-data memory envelope. Missing outcomes are
retained; downstream native inference requires its own exclusion policy.

## Domains and accounting

`nis_domain(design, field, missing)` accepts a retained plain logical indicator
or a bounded one-sided predicate formula, for example:

```r
domain <- nis_domain(design, ~ AGE >= 18 & cohort & !is.na(outcome),
  missing = "exclude")
```

Every referenced field must already be retained in the full or pooled design.
This selects after construction; it is not a filter on the source Parquet files.
The formula accepts comparisons `==`, `!=`, `<`, `<=`, `>`, `>=`, logical `&`,
`|`, `!`, parentheses and `is.na`. `%in%` accepts a literal scalar or `c()` of
literal constants on its right side. Negative numeric constants are permitted.
Numeric, logical, character and standard factor fields are supported; other
classed fields, matrices and observed numeric infinities are refused. Logical
operators require logical operands, so numeric flags need an explicit comparison
such as `flag == 1`. A predicate must reference at least one retained field and
return one plain logical value per supplied discharge.

Predicates use fixed base operators and exact retained field names; formula
environments/terms metadata, globals, caller functions, indexing, namespaces,
arithmetic, assignments and sample-dependent functions are unsupported. A field
with spaces is quoted with R backticks. No text is parsed as code. Warnings from
invalid comparisons, such as ordering an unordered factor, reject the call.

Choose `missing = "fail"` or `"exclude"`. Exclusion records unknown indicators
separately from FALSE rows. Repeated domains retain their sequential accounting.
Empty domains are allowed to describe an empty selection, without an inference
claim. The original wrapper and full-population accounting are preserved.
Missingness concerns the final evaluated predicate, using base R meanings:
`FALSE & NA` is FALSE, `TRUE & NA` is unknown, `is.na()` explicitly tests missing
values and `%in%` returns TRUE/FALSE even for NA (matching NA if declared in the
constant set). Raw negative sentinels and factor labels are not decoded or
recoded. Filtering numeric outcomes with special missing codes requires a
separately reviewed field contract; `is.na()` does not discover those codes.

String-field domain history keeps its existing `field` declaration. Predicate
history records the expression and referenced `fields`, followed by the same
supplied/included/FALSE/unknown accounting and explicit missingness policy.
No temporary indicator column is inserted. Raw columns, original population,
constructor provenance, caller formulas/options and earlier results are unchanged.

The native subsetting method retains original PSU information, including
hospitals with no domain members. Rebuilding a design from just the selected
rows loses that information. Aggregate population counts report discharges,
hospitals, strata, full-design degrees of freedom and singleton strata. A
domain's effective degrees of freedom can differ; use native `survey` methods
and an explicit inference policy for any subsequent interval or test.
`nis_estimate()` records these native values separately from caller-selected
interval degrees of freedom.

easyNIS does not set global survey options. First loading `survey` initializes
its own defaults while preserving caller settings. Construction records those
initial options and the survey version. Later native calls use the options in
force at that time; this wrapper does not certify downstream estimates.

## Independent evidence and limits

The method contract follows the cluster, stratum, weight and full-sample domain
examples in [HCUP Methods Series 2015-09](https://hcup-us.ahrq.gov/reports/methods/2015-09.pdf),
pages 10-15, and the [native domain-subsetting documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/subset.survey.design.html).
Installed `survey` 4.5 documentation explains its no-FPC replacement assumption.
These methodological sources do not replace saved annual source layouts,
conversion provenance or author review.

One invented case has two strata, two hospitals per stratum and domain members
in only one hospital per stratum. Domain hospital weights total 9 and 9, and
weighted LOS totals are 22 and 29. The independent WR variance is 22^2 + 29^2
for the LOS total. The mean is 51/18; its linearized variance is
(3.5^2 + 3.5^2)/18^2. The domain-weight total is 18 with variance 9^2 + 9^2.
Small deterministic double calculations use a 1e-12 comparison tolerance.

Tests also compare direct survey calls, retain missing outcomes and exact large
identifiers, accept valid zero estimates and variances, reject invalid weights
and singleton/conflicting mappings, and preserve nondefault caller options.
Scientific approval by Saad and Ali, annual metadata, licensed reference
validation, model reports and export safeguards remain separate gates.
Compound-predicate tests additionally prove exact native subsetting/PSU parity,
independent WR total/mean variance with absent-domain hospitals, pooled year
keys, repeated/empty domains, raw sentinels/factor labels, unknown counts, literal
membership, fixed-function evaluation and rejection of unsafe formulas or masks.
