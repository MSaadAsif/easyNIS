# Create a new NIS study folder

Copy the packaged Quarto study template to a new directory. The
destination must not already exist.

## Usage

``` r
nis_new_study(path)
```

## Arguments

- path:

  A new local directory path for the study.

## Value

The normalized path to the created study directory.

## Examples

``` r
study_path <- tempfile("nis-study-example-")
nis_new_study(study_path)
#> [1] "/tmp/Rtmpvq05CD/nis-study-example-1a5b4b3575b7"
list.files(study_path, all.files = TRUE, no.. = TRUE)
#> [1] ".gitignore"   "_quarto.yml"  "analysis.qmd"
```
