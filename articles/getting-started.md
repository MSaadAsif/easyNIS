# Get started with easyNIS

This guide opens invented discharges, defines a diagnosis cohort, builds
a survey design, estimates weighted summaries, and checks disclosure.
All input comes from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md);
it contains no real NIS records and results are for learning only.

## Open annual data

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
scans Parquet files lazily. Collect only a small summary when you need
to inspect records.

``` r

nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpGrrjvh/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpGrrjvh/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpGrrjvh/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(YEAR) |> dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
#> 2  2019    96
```

The counts here describe the synthetic fixture by year. See [Opening NIS
data](https://msaadasif.github.io/easyNIS/articles/opening-data.md) for
column selection, engines, and year coverage.

## Define a cohort

Flags check each diagnosis slot independently. Prefixes are analyst
supplied; easyNIS does not choose a clinical definition.

``` r

nis <- nis |> nis_flag_dx(heart_failure = "I50")
nis |> dplyr::count(heart_failure) |> dplyr::collect()
#> # A tibble: 2 × 2
#>   heart_failure     n
#>   <lgl>         <dbl>
#> 1 TRUE            108
#> 2 FALSE            84
```

The two rows show fixture records with and without a matching code.
Review positions and code-system assumptions before using a flag; see
[Defining
cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.md).

## Build a survey design

The cohort is declared inside
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
This preserves sampled hospital-year information when no discharges meet
the cohort.

``` r

design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 18,
  keep = c(AGE, FEMALE, LOS),
  annualize = TRUE
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 108 discharges; weighted N 62.4; 18 hospitals across 2 years.
```

For a pooled design, `annualize = TRUE` divides discharge weights by the
number of valid years. The rule treats each included year as a whole
year; read [Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md)
before choosing it for a real analysis.

## Estimate weighted summaries

Use survey-aware summaries so standard errors account for strata and
hospitals.

``` r

srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_los = srvyr::survey_mean(LOS)
)
#> # A tibble: 1 × 4
#>   discharges discharges_se mean_los mean_los_se
#>        <dbl>         <dbl>    <dbl>       <dbl>
#> 1       62.4          8.67     5.66       0.229
```

The estimated total and mean describe the fixture under its design
fields, not national estimates. The standard errors are design based;
ordinary row-level summaries would not represent this sampling design.

## Review disclosure

[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
reports unweighted discharges and distinct year-scoped hospitals for
each output cell.

``` r

records <- dplyr::collect(nis)
cells <- nis_cell_counts(records, by = "heart_failure")
nis_suppress(cells, count_col = "n", hospital_col = "hospitals")
#> # A tibble: 2 × 3
#>   heart_failure n     hospitals
#>   <lgl>         <chr> <chr>    
#> 1 FALSE         84    24       
#> 2 TRUE          108   18
```

Suppressed rows either meet the configured small-cell threshold or
represent fewer than two hospitals. Review derived totals and follow the
applicable HCUP Data Use Agreement. See [Disclosure and
suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.md).

## Common pitfalls

> **Common pitfalls**
>
> - Filtering to the cohort before building the design drops sampled
>   hospital-years with no cohort records.
> - Treating the invented fixture’s estimates as national results.
> - Sharing a masked table without reviewing totals and other derivable
>   cells.

The exported
[`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md)
helper can copy a Quarto study skeleton; its template workflow is
deferred. Start with the articles and function reference for a complete
analysis workflow.
