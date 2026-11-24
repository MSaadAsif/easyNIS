# Contributing

Thanks for helping improve easyNIS. Changes should be reviewable, supported by invented public fixtures, and consistent with the package's documented limitations.

## Setup

1. Fork the repository and create a branch for your change.
2. Open the repository root in RStudio or set it as your working directory.
3. Install development dependencies with `pak::pak(".", dependencies = TRUE)`.
4. For documentation changes, install `roxygen2` and `pkgdown`; for lint checks, install `lintr`.

## Change and verify

- Keep each branch focused and describe the user-visible behavior in the pull request.
- Add or update focused `testthat` coverage using invented fixtures. Do not create examples from licensed NIS inputs or record-derived output.
- Regenerate documentation with `devtools::document()` when roxygen comments change, and include the generated `man/` and `NAMESPACE` changes.
- Run relevant tests with `devtools::test()`, then run `devtools::check()` before requesting review. Run `lintr::lint_package()` for style changes and `pkgdown::check_pkgdown()` for pkgdown configuration changes.
- Follow the existing style: tidyverse formatting, explicit package namespaces in examples where appropriate, and clear warnings for experimental behavior. CI runs package checks, lint, and coverage.
- Work on a branch. An independent reviewer reviews the diff; merge only after review and checks pass.

## Where changes belong

R loads package source from the flat `R/` directory. Use the domain in the
filename and put focused tests next to that domain's other tests in
`tests/testthat/`.

| To change | Start here |
| --- | --- |
| Annual and Hive discovery | `R/open.R` for part selection, `R/open-parquet.R` for scan planning and year validation, and `R/duckdb.R` for connections and spill storage |
| Diagnosis or procedure selection | `R/code-layout.R` for slot names and code-system eligibility, `R/code-flags.R` for matching, and `R/procedure-days.R` for PRDAY decoding |
| Survey design or weights | `R/design.R` for input and cohort selection, `R/cohort-design.R` for the survey representation, and `R/reweight.R` for factor validation and application |
| Disclosure | `R/disclosure-policy.R` for primary masks and hospital identity, and `R/suppress-survey.R` or `R/suppress-data-frame.R` for format-specific behavior |
| Generated studies | `R/study-scaffold.R` for files, `R/study-cache.R` for cache inputs, `R/study-model.R` for fit diagnostics, and `inst/templates/nis-study/` for the report |
| Improvement probes | `tools/probe/` for commands, `quality-checks.R` for check definitions, `quality-receipts.R` for evidence, and `readiness-criteria.R` for decisions |

Keep I/O and format-specific code at the entry points. Put a rule in a shared
module when multiple callers need the same rule, and exercise it through the
normal user-facing functions.

## Privacy and licensing

Use invented fixtures and independently authored code compatible with the project's AGPL-3.0-only license. Do not add licensed HCUP inputs, real or record-derived records, private paths, local validation receipts, or output that could disclose individual-level information. Never share record-level NIS data. Review tables for primary and complementary disclosure risks and follow the HCUP Data Use Agreement and institutional requirements.

## Pull requests

Explain the behavior changed, relevant verification, and remaining methodological or annual-layout limitations. Use the pull request checklist and keep the change focused.
