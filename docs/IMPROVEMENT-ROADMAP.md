# Path to 1.0

The improvement loop in [LOOP.md](LOOP.md) turns real workflow friction and
package checks into reviewed fixes. `tools/probe/readiness.R` reports the
current status of each criterion below; evidence stays local when it contains
real NIS results.

## Ready criteria

1. **R CMD check --as-cran:** zero errors, warnings, and notes on CI. See the
   `R CMD check --as-cran` criterion in `readiness.R`.
2. **rOpenSci packaging guide:** conform to the packaging guide. See
   `rOpenSci packaging-guide conformance`.
3. **Coverage:** test coverage is at least 90%. See `Test coverage >= 90%`.
4. **Examples:** every exported function has runnable examples. See
   `Every export has runnable examples`.
5. **Workflow documentation:** pkgdown documents the full analyst workflow.
   See `pkgdown documents the full workflow`.
6. **Complexity:** cyclomatic complexity is at most 15 for every function.
   See `Cyclomatic complexity <= 15 per function`.
7. **Published-study verification:** reproduce headline estimates from three
   published NIS studies within a stated tolerance. Run verification locally
   against licensed data; publicly record only pass/fail and tolerance, never
   estimates or record-derived values. See the matching readiness criterion.
8. **Issue severity:** no open P0 or P1 issues. See `No open P0/P1 issues`.

## Scope decisions

- Defer the synthetic template study (Phase D/R8). The completed HOCM
  myectomy-versus-ablation study remains a reference, not new work.
- HOCM backlog item #8 (Elixhauser) may proceed only as a thin wrapper over an
  existing package such as `comorbidity` or `medicalcoder`; easyNIS must not
  implement the algorithm or maintain code sets.
- HOCM backlog item #3 (curated cardiac device code sets) remains deferred.
- Keep easyNIS focused on a simple NIS analyst workflow built on established
  packages including `survey`, `srvyr`, `gtsummary`, `comorbidity` or
  `medicalcoder`, `arrow`, and `duckdb`.

## Completed history

The literature challenge set reviewed 12 original NIS studies and established
the existing survey workflow as the core product direction. The HOCM study is
complete. Repository comparison tests for `nis_design()` use invented data;
they are not independent external validation.
The archived research report is `docs/research/2026-10-nis-literature-report.md`.

## Report corrections

The archived report's claim that no `nis_design()` validation artifact exists
is corrected above: repository comparison tests exist, but independent external
validation remains a Path to 1.0 criterion.

## Out of scope

- Broad pre-2012 support, including `TRENDWT`, before annual layouts are verified.
- Person-level linkage, longitudinal or readmission helpers, and state estimates.
- Post-2011 hospital volume inferred from sampled discharge counts.
- Wrappers for general statistical methods already supported by established R
  packages, or preflight tools that choose scientific assumptions for analysts.
