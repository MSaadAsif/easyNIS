# Survey design validation protocol

This protocol compares the placeholder-row design returned by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
with a survey design built from the full invented data, before domain
subsetting. Fixtures come from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
and contain no licensed records.

## Run a synthetic design summary

The example below builds a domain design from invented discharges and
reports a weighted mean. Its values demonstrate the output structure;
they are not NIS estimates.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpfTHmPI/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpfTHmPI/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpfTHmPI/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 18,
  keep = c(AGE, LOS)
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.
srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_age = srvyr::survey_mean(AGE)
)
#> # A tibble: 1 × 4
#>   discharges discharges_se mean_age mean_age_se
#>        <dbl>         <dbl>    <dbl>       <dbl>
#> 1       125.          17.3     57.6       0.987
```

The total and mean are design-based summaries of the synthetic cohort.
The standard errors use the NIS-style strata and hospital structure
supplied in the fixture.

## Cases

- Complete pooled years (2017–2019), with cohort and non-cohort
  discharges across hospitals and years.
- Complete 2015 and 2016 data with a cohort limited to Q4 2015, which
  tests detection of the ICD-10-coded era.
- Invalid design rows in the input; the reference removes the same rows
  failing positive, finite `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or
  `DISCWT` checks.
- Annualized weights, divided by the count of valid-design years,
  including the partial year as one year.
- A rare cohort represented in only one quarter of a full data year is
  silent; pre-filtering the data to Q1-Q3 warns because valid-design
  data then has only three quarters.
- A Q4-only cohort in 2015 warns that it covers the ICD-10-coded part of
  the year, while a complete cohort year is silent. Without `DQTR`, the
  2015 split cannot be checked and an informational message says so.

Quarter coverage is computed by grouping valid-design rows in the lazy
query by `YEAR` and `DQTR`, then collecting that small summary.
Cohort-quarter checks use only true cohort discharges, so zero-domain
placeholder rows do not affect the result.

## Compared statistics

At absolute tolerance `1e-8`, compare survey means and standard errors,
weighted totals and standard errors, `svyratio()` estimates and
variance, [`confint()`](https://rdrr.io/r/stats/confint.html) for means,
`svyby()` estimates and standard errors, logistic and Gaussian
`svyglm()` coefficients and covariance matrices, and median
`svyquantile()` estimates. Compare design degrees of freedom exactly and
the gtsummary p-values at `1e-8`. Annualized totals are compared with
full-data reference totals divided by the number of valid-design years.

## Reference construction

Start from collected
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
data and compute `.in_cohort` for every row. Build year-qualified PSU
and stratum identifiers and use original or annualized `DISCWT` values
in `srvyr::as_survey_design(..., nest = TRUE)`. Apply
`dplyr::filter(.in_cohort)` only after constructing that full-data
design. For invalid-row cases, filter out exactly the rows that
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
excludes before building the reference. This preserves non-cohort
observations in each hospital-year so domain estimates have the same
sampling structure.

## Common pitfalls

> **Common pitfalls**
>
> - Comparing a design created after filtering to the full-design domain
>   reference does not test the same variance calculation.
> - Use invented fixture outputs only to check mechanics, not inference.
> - Agreement in the listed cases does not validate assumptions beyond
>   those cases.

See
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
and [Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md).
