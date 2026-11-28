# Reweight a cohort survey design

Multiply the cohort's discharge weights by prespecified analysis
factors.

## Usage

``` r
nis_reweight(design, weights)
```

## Arguments

- design:

  A result of
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
  Column selection, renaming, and mutation are supported when cohort
  rows are unchanged. Required internal design fields are restored from
  survey metadata; removed analysis columns are not restored.

- weights:

  Numeric weights aligned with the cohort rows of `design`, or an
  unquoted numeric column name in the design data. They are matched to
  rows by position, so take them from `design$variables` in that order
  (for example, fit the propensity model on `design$variables`) and do
  not reorder or subset the rows first.

## Value

A filtered [`srvyr::tbl_svy`](http://gdfe.co/srvyr/reference/tbl_svy.md)
survey design.

## Details

The design retains the original hospital and stratum structure.
Uncertainty estimates treat the supplied factors as fixed.

## See also

[Make tables and fit survey
models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html),
[Make tables and fit survey
models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html).

Other survey-design:
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md),
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)

## Examples

``` r
nis <- nis_open(nis_example(2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpepKHEX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpepKHEX/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, AGE >= 18, keep = c(AGE, LOS))
#> Preparing the cohort survey design.
reweighted <- nis_reweight(design, ifelse(AGE >= 65, 1.2, 0.9))
srvyr::summarise(reweighted, mean_los = srvyr::survey_mean(LOS))
#> # A tibble: 1 × 2
#>   mean_los mean_los_se
#>      <dbl>       <dbl>
#> 1     5.41       0.151
```
