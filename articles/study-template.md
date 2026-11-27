# Start a Quarto study

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

``` r

study <- nis_new_study(tempfile("nis-study-"))
list.files(study, all.files = TRUE, no.. = TRUE)
#> [1] "_quarto.yml"  ".gitignore"   "analysis.qmd"
```

Install Quarto and the R packages `purrr`, `survey`, `srvyr`, and
`gtsummary`. Use a new directory in a private workspace. Open
`analysis.qmd` and render it from that directory with
`quarto render analysis.qmd`. The template uses
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
while `data_path` is unset.

## Use your annual files

In the report’s YAML, set `params.data_path` to the directory containing
your prepared annual Parquet files. Set the years and revise the code
definitions, eligibility criteria, endpoints, and analysis for your
study. Render the report again. [Prepare annual NIS
files](https://msaadasif.github.io/easyNIS/articles/prepare-data.md)

## Review the methods and checklist

Read the generated methods paragraph alongside the design and cohort
outputs. Check the sample definition, weighting convention, and model
denominators. The checklist receipt records package checks and items
that need your review. Check disclosure across the rendered tables and
figures before sharing the report.
