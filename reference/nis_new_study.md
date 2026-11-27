# Create a new NIS study folder

Create a Quarto study in a new local directory.

## Usage

``` r
nis_new_study(path)
```

## Arguments

- path:

  A new local directory path for the study.

## Value

The normalized path to the created study directory.

## Details

Open `analysis.qmd` to edit the cohort, outcomes, and analysis. Render
with `quarto render analysis.qmd` from the study directory. With
`params.data_path` unset, the report uses
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md).
Set that parameter to the private directory containing your annual
Parquet files.

Review the rendered methods paragraph and checklist receipt against the
study protocol. Review disclosure across the finished report before
sharing it.

## See also

[Start a Quarto
study](https://msaadasif.github.io/easyNIS/articles/study-template.html),
[Start a Quarto
study](https://msaadasif.github.io/easyNIS/articles/study-template.html).

## Examples

``` r
study_path <- tempfile("nis-study-example-")
nis_new_study(study_path)
#> [1] "/tmp/RtmpDuFgaD/nis-study-example-190d5203ff66"
list.files(study_path, all.files = TRUE, no.. = TRUE)
#> [1] ".gitignore"   "_quarto.yml"  "analysis.qmd"
```
