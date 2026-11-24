# Create a study

## Sub-features

Generate a Quarto study directory, then render the starter HTML report with
its built-in invented inputs.

## How to get to it (user POV)

Call `nis_new_study()` with an unused directory path, then run
`quarto render analysis.qmd --to html` from the new directory.

## Driving it with Rscript

Keep Quarto on PATH and install `purrr`, `survey`, `gtsummary`, `cardx`,
`gt`, `knitr`, `rmarkdown`, and `broom.helpers` in your normal R library.

```sh
Rscript --vanilla .agents/skills/verify/drive.R study
```

The driver verifies the generated project files, renders with the scaffold's
default `nis_example()` data, and verifies the study title and cohort-flow
section in the HTML. Inspect `scaffold.txt`, `analysis.qmd`, `render.txt`,
and `analysis.html`. Compare the rendered tables or model output when they
are the subject of the change.

## Gotchas

The report runs in a separate process. The driver points Quarto to the same
R installation and the temporary library used to install the checkout.
This journey covers HTML. A Word-specific change also needs a Word render
with `quarto render analysis.qmd --to docx` and `flextable` installed.
