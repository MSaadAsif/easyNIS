# Create a study

## Sub-features

Generate a Quarto study directory, then render the report with built-in or
explicit invented inputs.

## How to get to it (user POV)

Call `nis_new_study()` with an unused directory path, then run
`quarto render analysis.qmd --to html` from the new directory.

## Driving it with Rscript

Keep Quarto on PATH and install the package's suggested dependencies and
`xml2` in your normal R library.

```sh
Rscript --vanilla .agents/skills/verify/drive.R study
Rscript --vanilla .agents/skills/verify/drive.R study-ci
```

The `study` journey renders the default scaffold with built-in example
data. The `study-ci` journey supplies a synthetic Parquet directory and
edits the cohort definition to include some discharges outside the principal
diagnosis group. It renders HTML and Word and verifies the four HTML
cohort-flow rows against the fixture.

Both journeys check the rendered sections and the disclosure notice.
`study-ci` also checks that the explicit input directory is absent from
the HTML. Inspect the scaffold, render logs, and reports in the evidence
directory. The CI journey records its fixture hashes and the expected and
observed cohort flow.

## Gotchas

The report runs in a separate process. The driver points Quarto to the same
R installation and the temporary library used to install the checkout.
The Word render also requires `flextable`. In CI the evidence is uploaded
as `synthetic-study-render`.
