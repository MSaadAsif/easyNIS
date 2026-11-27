# Get started with easyNIS

This workflow uses invented inpatient discharges from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md).
In a study, use the path to your converted annual Parquet files and
supply your own diagnosis definitions and eligibility rules.

## Open, project, and flag

Choose the study years in
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).
Select the columns needed for the analysis, keeping the design fields
and the diagnosis slots used by the flag. The query stays in DuckDB. The
diagnosis flag checks every slot by default.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  dplyr::select(nis_vars_design(), nis_vars_dx(), AGE, FEMALE, LOS, DIED, DISPUNIFORM) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_outcomes() |>
  dplyr::mutate(adult = AGE >= 18)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYqeEvn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYqeEvn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

nis_attrition(nis, adult = adult, by_year = TRUE, .design = TRUE)
#> # A tibble: 4 × 8
#>    YEAR  step criterion             n_unweighted n_dropped_unweighted n_weighted
#>   <int> <int> <chr>                        <int>                <int>      <dbl>
#> 1  2020     0 Valid design dischar…           96                   NA       114.
#> 2  2020     1 adult                           96                    0       114.
#> 3  2019     0 Valid design dischar…           96                   NA       114.
#> 4  2019     1 adult                           96                    0       114.
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
```

[`nis_vars_design()`](https://msaadasif.github.io/easyNIS/reference/nis_vars_design.md)
keeps `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, `DISCWT` and, when present,
`DQTR`. If a prior selection removed one of the four required fields,
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
reports the missing field. See [Defining
cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.md) for
principal diagnoses, exclusions, procedure flags, and code-system
choices.

## Estimate within the adult domain

Pass the eligibility flag to `cohort` so the variance calculation can
account for sampled hospital-years with no eligible discharges. `keep`
limits what the design brings into R, and the design labels retained
HCUP fields. The flag groups compare adult discharges with and without a
matching diagnosis.

``` r

design <- nis |>
  nis_design(cohort = adult, keep = c(heart_failure, AGE, FEMALE, los_days, in_hospital_death))
#> Preparing the cohort survey design.

estimates <- design |>
  dplyr::group_by(heart_failure) |>
  dplyr::summarise(
    discharges = srvyr::survey_total(),
    mean_los = srvyr::survey_mean(los_days, na.rm = TRUE)
  )
```

This estimates totals across both study years. Use `annualize = TRUE`
for average annual totals when each included year represents a whole
year. For annual estimates, keep the original weights and group by
`YEAR`. See [Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md)
for pooling and coverage.

## Make a table and fit a model

Use the same design for the descriptive table and regression. The model
adjusts for age, sex, and year in this invented example. Review the
model sample and missingness when reporting a real analysis.

``` r

table_one <- design |>
  gtsummary::tbl_svysummary(by = heart_failure, include = c(AGE, FEMALE, los_days, in_hospital_death))
nis_suppress(table_one)
```

[TABLE]

``` r

fit <- survey::svyglm(
  in_hospital_death ~ heart_failure + AGE + FEMALE + factor(YEAR),
  design = design,
  family = quasibinomial()
)
```

## Review disclosure before exporting

The table above masks statistics using corresponding unweighted counts
and hospital support. For a data-frame summary, attach those counts
explicitly. This fixture has recorded LOS for every discharge. With
missing LOS, use counts for the records contributing to that mean.

``` r

reviewed <- estimates |>
  dplyr::left_join(nis_cell_counts(design, by = heart_failure), by = "heart_failure") |>
  nis_suppress(
    count_col = "n",
    hospital_col = "hospitals",
    weighted_cols = c("discharges", "discharges_se", "mean_los", "mean_los_se")
  )
reviewed
#> # A tibble: 2 × 7
#>   heart_failure discharges discharges_se    mean_los mean_los_se n     hospitals
#>   <lgl>         <chr>      <chr>            <chr>    <chr>       <chr> <chr>    
#> 1 FALSE         104        19.9077874210069 5.38076… 0.27278462… 84    24       
#> 2 TRUE          124.8      17.3481987537612 5.66346… 0.22899117… 108   18
```

Review disclosure across tables, models, and related totals before
sharing. Keep work in a private directory. See [Disclosure and
suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.md).

``` r

utils::write.csv(reviewed, "discharges-reviewed.csv", row.names = FALSE)
```

## Project before collecting

When a step needs a data frame, put `select()` before `collect()` so
DuckDB can read the requested columns from Parquet. In a Windows
benchmark, fresh R 4.6.1 processes with DuckDB 1.5.2 selected the same
seven columns from 480,000 invented rows and 188 source columns. Peak
process commit was 206 MiB with projection before collection and 1,379
MiB with projection after collection. The difference measures one
synthetic workload. Peak memory depends on the data, query, and system.

To reproduce the measurement from the easyNIS source directory on
Windows, install the package and run these commands with a new scratch
directory.

``` sh
Rscript --vanilla tools/benchmark-column-projection.R prepare local/loop/wide-invented
Rscript --vanilla tools/benchmark-column-projection.R early local/loop/wide-invented
Rscript --vanilla tools/benchmark-column-projection.R late local/loop/wide-invented
```
