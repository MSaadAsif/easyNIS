# Offline synthetic workflow

The installed yearly drive uses `nis_factor()` to create an explicit analysis
factor while retaining the raw character field and native cluster information.
Its fitted coefficients/covariance and factor-support counts must exactly match
the existing separate factor construction for every invented year label. Require
caller-declared/unverified mapping provenance and unchanged population/domains.
Unit references additionally cover numeric/logical/character mappings, exact
numeric categories, NA/NaN, unknown-value rejection, unused levels, pooled keys,
caller contrast schemes, independent WR models and unchanged raw/design state.

Run `tools/verify.ps1`. The installed smoke sources
`system.file("examples/synthetic-workflow.R", package = "easyNIS")` twice in
fresh environments. Both calls must produce new output directories with
identical report, CSV and HTML contents. Compare the shown LOS mean, SE and
interval with the independent hospital WR reference in `docs/WORKFLOW.md`.
Check its 48 observed domain discharges, the hidden rare row, no audit columns
and matching primary suppression in HTML. Check report versions and explicit
policies, relative links and absence of source paths, raw identifiers and
retained result objects. Only invented data may be used. This example does
not validate any annual capability or scientific policy.

The source build/check executes `vignettes/synthetic-workflow.Rhtml` with the
knitr HTML engine, without Pandoc. The installed smoke requires its vignette
index and rendered HTML, confirms the reviewed table and blank suppressed
cells, and rejects temporary source paths in the rendered walkthrough.

The installed single-year drive also calls `nis_models()` with one shared
intercept declaration and Gaussian LOS, logistic domain and Poisson exposure
outcomes for every invented 2017–2022 label. Compare the individual fits and
batch results exactly, and check all three coefficients/SEs against independent
hospital WR arithmetic. Require separate sample rows, stable outcome ordering,
pointwise provenance and `analysis_ready = FALSE`. Unit references additionally
cover full/domain/pooled designs, outcome-specific missingness, year-specific
keys, warning/alias retention and failed-batch rejection. No batch is published.

The installed smoke also runs `examples/pooled-model-workflow.R` twice.
Require six complete annual designs, 24 year-specific hospitals and 12 strata,
pooling before domain selection, average annual weight divisor 6, independent
mean 172/21 and total 4816 with WR SEs, and matching Gaussian intercept inference.
Check 288 observed/72 missing model outcomes, a hidden rare descriptive row,
fixed model-scale/pooling declarations, repeatable output bytes and no raw model
results or local paths in artifacts. Both vignette tables must have blank
suppressed numeric/count cells. Reference derivations are in docs/WORKFLOW.md.

The pooled example additionally composes `nis_factor()`, a bounded adult/code
predicate and a shared-predictor LOS/event batch. Require 288/354 included and
72/6 missing outcomes from 360 invented domain rows, independent GLM/WR matrix
references for both links and unchanged scalar descriptive references. The
repeat run starts from nondefault survey/contrast options and must restore them
while producing identical bytes. Check fixed factor/batch/domain declarations
in the report, absence of model coefficient/sample-accounting leakage, and the
new walkthrough/migration text with the same two reviewed vignette tables.

The six-year example opts in to two lowercase quality markers per year in
invented noncohort rows. Require raw/flag key alignment before construction,
distinct retained reasons, 12 explicitly excluded unknown pooled predicates,
348 false predicates and unchanged 360 domain rows and numerical references.
The report declares this experimental policy without clinical or annual approval.
