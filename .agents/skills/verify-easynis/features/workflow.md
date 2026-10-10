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
