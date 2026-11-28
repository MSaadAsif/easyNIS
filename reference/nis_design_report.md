# Report the survey design and fitted sample

Report the discharges and survey weights used in a design or fitted
model.

## Usage

``` r
nis_design_report(x)
```

## Arguments

- x:

  A
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  result, including a filtered or reweighted design, or a
  [`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fit
  made with that design.

## Value

A `nis_design_report` list with the valid-design input years, input and
original cohort counts, design-field exclusions, cohort criterion, and
current domain count. Weighting fields describe the base weight column,
annualization divisor, and whether supplied reweights were applied. The
PSU and stratum fields name their year-scoped keys. For a fit,
`domain_n` counts the records after any model subset and before the
fit's missing-data action. The `model` entry gives the fitted unweighted
count (`n`, from [`stats::nobs()`](https://rdrr.io/r/stats/nobs.html))
and the number of records the fit omitted for missing model data
(`excluded_n`). The print method summarizes sample stages and weighting.
Use `$` to access details such as `excluded`.

## Details

Use the report to reconcile input, cohort, and analysis counts. After
filtering a design, the current domain count changes while the original
sample count is retained. Review disclosure before sharing the report.

## See also

[Analyze your first NIS
cohort](https://msaadasif.github.io/easyNIS/articles/getting-started.html)

Other survey-design:
[`nis_annual_totals()`](https://msaadasif.github.io/easyNIS/reference/nis_annual_totals.md),
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md),
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)

## Examples

``` r
data <- nis_open(nis_example(2019:2020))
design <- nis_design(data, AGE >= 18, keep = c(AGE, LOS), annualize = TRUE)
nis_design_report(survey::svyglm(LOS ~ AGE, design = design))
#> NIS design report
#> Years: 2019, 2020
#> Weights: DISCWT / 2
#> # A tibble: 4 × 2
#>   stage           discharges
#>   <chr>                <dbl>
#> 1 Input sample           192
#> 2 Original cohort        192
#> 3 Current domain         192
#> 4 Fitted model           192
```
