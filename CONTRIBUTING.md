# Contributing

Thanks for helping improve easyNIS. Changes should be reviewable, supported by invented public fixtures, and consistent with the package's documented limitations.

## Setup

1. Fork the repository and create a branch for your change.
2. Open `easyNIS.Rproj` in RStudio or set the repository as the working directory in R.
3. Install development dependencies with `pak::pak(".", dependencies = TRUE)`.
4. For documentation changes, install `roxygen2` and `pkgdown`; for lint checks, install `lintr`.

## Change and verify

- Keep each branch focused and describe the user-visible behavior in the pull request.
- Add or update focused `testthat` coverage using invented fixtures. Do not create examples from licensed NIS inputs or record-derived output.
- Regenerate documentation with `devtools::document()` when roxygen comments change, and include the generated `man/` and `NAMESPACE` changes.
- Run relevant tests with `devtools::test()`, then run `devtools::check()` before requesting review. Run `lintr::lint_package()` for style changes and `pkgdown::check_pkgdown()` for pkgdown configuration changes.
- Follow the existing style: tidyverse formatting, explicit package namespaces in examples where appropriate, and clear warnings for experimental behavior. CI runs package checks, lint, and coverage.
- Work on a branch. An independent reviewer reviews the diff; merge only after review and checks pass.

## Privacy and licensing

Use invented fixtures and independently authored MIT-compatible code. Do not add licensed HCUP inputs, real or record-derived records, private paths, local validation receipts, or output that could disclose individual-level information. Never share record-level NIS data. Review tables for primary and complementary disclosure risks and follow the HCUP Data Use Agreement and institutional requirements.

## Pull requests

Explain the behavior changed, relevant verification, and remaining methodological or annual-layout limitations. Use the pull request checklist and keep the change focused.
