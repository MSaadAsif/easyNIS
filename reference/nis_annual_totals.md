# Estimate annual national discharge totals

Estimates one national total and design-based standard error per
calendar year using unscaled discharge weights. Give the function the
annual sample and declare the analysis domain with `cohort`. The design
uses year-specific hospital and stratum identifiers, as in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Usage

``` r
nis_annual_totals(
  .data,
  cohort,
  coding = c("single_era", "verified_comparable")
)
```

## Arguments

- .data:

  A data frame or lazy DuckDB query with the standard NIS design fields
  and `DQTR` (quarter numbers or `Q1`–`Q4` labels). All four quarters
  must have valid design records in each year. This coverage check
  cannot verify that the sample is complete.

- cohort:

  Logical expression defining the domain, passed to
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

- coding:

  Use `"single_era"` to require years within 2012–2014 or 2016 onward.
  Use `"verified_comparable"` to acknowledge the transition and confirm
  that the definition is coding-independent or an audit found no coding
  discontinuity between 2015 Q3 and Q4. A 2015 cohort confined to one
  coding era or with unknown discharge quarters is rejected.

## Value

A tibble ordered by `YEAR`, with `discharges`, `discharges_se`,
unweighted `n`, and distinct contributing `hospitals`. Years without
valid cohort discharges have zero support counts and missing estimates
and standard errors. Use the support counts with
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
before sharing annual estimates.

## See also

[Trends](https://msaadasif.github.io/easyNIS/reference/articles/trends.md).

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpvy8CIm/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpvy8CIm/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_annual_totals(nis, heart_failure)
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.
#> # A tibble: 2 × 5
#>    YEAR discharges discharges_se     n hospitals
#>   <int>      <dbl>         <dbl> <int>     <int>
#> 1  2019       62.4          12.3    54         9
#> 2  2020       62.4          12.3    54         9
```
