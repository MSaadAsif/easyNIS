# Contributing to easyNIS

Start from the ordered work in [the backlog](docs/BACKLOG.md). Describe the
behavior and validation evidence in an issue or pull request. New implementation
must be independent of easyNRD until reuse permission and licensing are resolved.

Agent development follows [the explicit-start policy](docs/AUTONOMY.md).
Use `tools/verify.ps1 -Doctor` and `tools/verify.ps1` for local verification.
Experimental development merges require current CI and independent agent review;
scientific validation and release approval remain separate.

Saad coordinates maintenance and API decisions. Saad and Ali review data
definitions, cohort rules, inference, and disclosure changes before release.
Muhammad Saad is the maintainer. Ali's preferred full public name and optional
ORCID remain pending; the current metadata uses the agreed name Ali. Report
development issues through the repository issue tracker.

Use entirely invented fixtures. Keep licensed inputs, converted records, study
outputs, private validation receipts, and reference-book copies outside tracked
files. Fixture dimensions are test choices; annual metadata requires official
source review and separate licensed validation.

The canonical roadmap is `inst/metadata/year-support.csv`. Change capability
states only with evidence described in [SUPPORT.md](docs/SUPPORT.md). Fixture
generation alone does not establish synthetic validation of an annual workflow.

With R and the suggested development packages installed, run from the checkout:

Documentation generation uses roxygen2 8.1.0, recorded in DESCRIPTION and pinned
in CI. Update both when changing the generator version.

```r
roxygen2::roxygenise()
testthat::test_local()
```

Then run in a terminal, substituting the built version if it changes:

```text
R CMD build .
Rscript tools/check-tarball.R easyNIS_0.0.0.9000.tar.gz
R CMD check --no-manual easyNIS_0.0.0.9000.tar.gz
```

The tarball check excludes private folders, record file formats, local books,
and development-only files. CI runs examples and tests on Windows, macOS,
Linux, R old release, and R devel. Refer to the PR checks for commit-specific
results; local Windows evidence does not establish every platform.
R 4.1 is the provisional language minimum, not a tested compatibility claim.

For a private input inventory, install the optional developer dependencies DBI
and duckdb, then run `Rscript tools/inventory-parquet.R <input-directory>
local-validation/parquet-inventory` as one terminal command. The tool queries
schemas and row counts from file footers and exports no discharge values.
Keep its output in the ignored `local-validation/` folder. It does not confirm
source counts, release revisions, conversion history, or annual support.

`tools/validate-local-parquet.R` runs the experimental importer and aggregate
structural checks against the six annual input directories. Run it with an
input directory and an ignored private output directory. It needs pkgload.
Its official-count comparisons do not authenticate merged components,
conversion provenance, derived scores, or survey inference.
