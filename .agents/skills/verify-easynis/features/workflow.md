# Offline synthetic workflow

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

The installed smoke also runs `examples/pooled-model-workflow.R` twice.
Require six complete annual designs, 24 year-specific hospitals and 12 strata,
pooling before domain selection, average annual weight divisor 6, independent
mean 172/21 and total 4816 with WR SEs, and matching Gaussian intercept inference.
Check 288 observed/72 missing model outcomes, a hidden rare descriptive row,
fixed model-scale/pooling declarations, repeatable output bytes and no raw model
results or local paths in artifacts. Both vignette tables must have blank
suppressed numeric/count cells. Reference derivations are in docs/WORKFLOW.md.
