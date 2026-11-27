# Contributing

Work on a focused branch. From the repository root, install development
dependencies with `pak::pak(".", dependencies = TRUE)` in R. Install
`devtools`, `callr`, and `cyclocomp` for checks, and put
[Air 0.13.0](https://posit-dev.github.io/air/cli.html) and
[Jarl 0.7.1](https://jarl.etiennebacher.com/#installation) on your PATH.

## Verify a change

- Before writing code, list what could fail. Prefer end-to-end tests of the
  public workflow with invented fixtures. Keep the inputs, exact command,
  platform, transcript, and observed results for each run. Follow
  [AGENTS.md](AGENTS.md) when a test needs isolation.
- Run relevant tests with `devtools::test()`. Keep tests fast and safe to run in
  parallel. Put slow tests behind `EASYNIS_FULL_TESTS` and keep CI on each push
  under 10 minutes.
- If roxygen comments change, run `devtools::document()` and commit the generated
  changes. Use the roxygen2 version in `DESCRIPTION`.
- Before committing, run `Rscript --vanilla tools/check-package.R --lint` for
  Air formatting, Jarl lint, and installed-package cyclomatic complexity of 15
  or less.
- Before opening the PR, run `Rscript --vanilla tools/check-package.R --full`.
  It runs `devtools::check()` on the exact commit with `EASYNIS_FULL_TESTS`
  enabled, isolated from the working tree and ignored data.

Describe what changed, how you verified it, and any remaining limitations in
the [PR template](.github/PULL_REQUEST_TEMPLATE.md). See the
[improvement loop](docs/LOOP.md) for orchestrated work and review.

## Where changes belong

Package code lives in `R/`, with related tests in `tests/testthat/`.

| To change | Start here |
| --- | --- |
| Opening annual or Hive data | `R/open.R` for the entry point, `R/open-discovery.R` for part ownership, `R/open-parquet.R` for scans, `R/open-release.R` for annual release checks, and `R/duckdb.R` for connections and spill storage |
| Diagnosis or procedure selection | `R/code-layout.R` for slots and code systems, `R/code-flags.R` for matching, and `R/procedure-days.R` for PRDAY decoding |
| Survey design or weights | `R/design.R` for input selection, `R/design-sample.R` for scans, `R/cohort-design.R` for survey objects, and `R/reweight.R` for reweighting |
| Disclosure | `R/disclosure-policy.R` for policy, `R/cell-counts.R` for summaries, and `R/suppress-survey.R` or `R/suppress-data-frame.R` for masking |
| Generated studies | `R/study-scaffold.R` for files, `R/study-cache.R` for caching, `R/study-model.R` for fit diagnostics, and `inst/templates/nis-study/` for the report |
| Improvement probes | `tools/probe/quality-checks.R` for checks, `tools/probe/quality-receipts.R` for evidence, and `tools/probe/readiness-criteria.R` for readiness |

For scan planning or DuckDB workload changes, run the
[bounded scan check and spill benchmark](.agents/skills/duckdb-parquet-scans/SKILL.md).

## Privacy and licensing

Keep licensed HCUP inputs, real records, private paths, and local validation
receipts out of the repository and public material. Never publish output from
real-data runs, including estimates, counts, or any record-derived values, in
issues, PRs, commits, or docs. Keep those outputs in Git-ignored `local/loop/`.
Review tables for primary and complementary disclosure risks. Follow the HCUP
Data Use Agreement and institutional requirements, and contribute independently
authored code compatible with AGPL-3.0-only.

Before posting an issue or PR body, save the text locally and run
`Rscript --vanilla tools/check-public-text.R path/to/body.md`. Check the text
yourself for private material even when the scanner passes.
