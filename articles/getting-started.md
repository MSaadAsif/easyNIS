# Analyze your first NIS cohort

Use invented discharges to build a cohort, make a Table 1, and fit a
survey-weighted model.

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
library(gtsummary)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

## Open the files and define the analysis groups

``` r

files <- nis_example(years = 2019:2020)
nis <- nis_open(files, years = 2019:2020) |>
  select(nis_vars_design(), nis_vars_dx(), AGE, LOS, DIED, DISPUNIFORM) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_outcomes()
```

`files` is a directory of annual Parquet files. The query keeps the
design fields and analysis columns. The flag checks every diagnosis slot
for `I50`.

## Estimate discharge totals and length of stay

``` r

design <- nis_design(
  nis, cohort = AGE >= 18,
  keep = c(AGE, heart_failure, los_days, in_hospital_death)
)

estimates <- design |>
  group_by(heart_failure) |>
  summarise(discharges = survey_total(), mean_los = survey_mean(los_days))
estimates
#> # A tibble: 2 × 5
#>   heart_failure discharges discharges_se mean_los mean_los_se
#>   <lgl>              <dbl>         <dbl>    <dbl>       <dbl>
#> 1 FALSE               104           19.9     5.38       0.273
#> 2 TRUE                125.          17.3     5.66       0.229
```

You get a weighted discharge total and mean length of stay for each
heart-failure group, with standard errors. Pass eligibility to `cohort`
so hospitals without adult discharges still count in the sampling
structure. The totals cover both years. [How easyNIS
works](https://msaadasif.github.io/easyNIS/articles/how-easynis-works.md)

## Make a table and fit a model

``` r

tbl_svysummary(
  design, by = heart_failure, include = c(AGE, los_days, in_hospital_death)
) |>
  nis_suppress() |>
  as_gt()
```

[TABLE]

The table compares the groups and masks cells with too few sampled
discharges or contributing hospitals.

``` r

fit <- survey::svyglm(
  in_hospital_death ~ heart_failure + AGE,
  design = design, family = quasibinomial()
)
summary(fit)$coefficients
#>                      Estimate Std. Error    t value     Pr(>|t|)
#> (Intercept)        0.46145631 0.98828434  0.4669267 6.468475e-01
#> heart_failureTRUE -0.63073217 1.21522210 -0.5190262 6.108471e-01
#> AGE               -0.09334641 0.01276033 -7.3153612 1.734965e-06
```

The heart-failure coefficient is the age-adjusted log odds ratio for
in-hospital death in this example.

## Check the design and export a summary

``` r

nis_design_report(design)
#> NIS design report
#> Years: 2019, 2020
#> Weights: DISCWT
#> # A tibble: 3 × 2
#>   stage           discharges
#>   <chr>                <dbl>
#> 1 Input sample           192
#> 2 Original cohort        192
#> 3 Current domain         192

reviewed <- estimates |>
  left_join(nis_cell_counts(design, by = heart_failure), by = "heart_failure") |>
  nis_suppress(
    count_col = n, hospital_col = hospitals,
    weighted_cols = c(discharges, discharges_se, mean_los, mean_los_se)
  )
file <- tempfile(fileext = ".csv")
write.csv(reviewed, file, row.names = FALSE)
read.csv(file)
#>   heart_failure discharges discharges_se mean_los mean_los_se   n hospitals
#> 1         FALSE      104.0      19.90779 5.380769   0.2727846  84        24
#> 2          TRUE      124.8      17.34820 5.663462   0.2289912 108        18
```

The design report records which years and weights entered the analysis
and how many sampled discharges met the criteria. Check support for each
statistic before export. For example, a mean with missing values needs
counts restricted to the records used for that mean. Review the release
across all outputs. [Check
disclosure](https://msaadasif.github.io/easyNIS/articles/disclosure.md)

## Where next

- [See examples in the output
  gallery](https://msaadasif.github.io/easyNIS/articles/gallery.md).
- [Prepare your annual
  files](https://msaadasif.github.io/easyNIS/articles/prepare-data.md).
- [Analyze the whole sample in
  DuckDB](https://msaadasif.github.io/easyNIS/articles/whole-sample.md).
- [Start a Quarto
  study](https://msaadasif.github.io/easyNIS/articles/study-template.md).
