# Create a lazy whole-sample NIS survey design

The nested, one-stage Taylor design uses hospital-year PSUs (YEAR ×
HOSP_NIS) and year-specific strata (YEAR × NIS_STRATUM), without a
finite population correction. It uses the valid-design discharges in the
input query. Apply eligibility restrictions with
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
on the design so hospitals outside the domain still contribute to
variance. Use [`subset()`](https://rdrr.io/r/base/subset.html) as the
survey-style alternative. A query filtered before construction defines a
different sample.

## Usage

``` r
nis_survey(.data, weights = DISCWT)
```

## Arguments

- .data:

  A lazy DuckDB query from
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).

- weights:

  A data-masked SQL-translatable expression for the analysis weights.
  The default uses discharge weights without annualization.

## Value

A lazy `nis_survey` design.

## Details

Use
[`survey::svymean()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
[`survey::svytotal()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
or [`survey::svyby()`](https://rdrr.io/pkg/survey/man/svyby.html) with
one-sided formulas. Grouped estimates support means and totals. Use
[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) for
additive models with Gaussian identity, binomial or quasibinomial logit,
and Poisson or quasipoisson log families. Wald inference uses the sample
design degrees of freedom minus the fitted model rank plus one. DuckDB
computes weighted sums by PSU without collecting discharge records. The
analysis supports the `"fail"` and `"adjust"` values of
`survey.lonely.psu` and honors `survey.adjust.domain.lonely`. Use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
for row-level operations such as quantiles, chi-square tests, model
diagnostics, and
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).

Discharges with missing, non-finite, or nonpositive design fields
(`YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT`) are excluded. Custom
analysis weights must be positive and finite within the domain.

## See also

Other survey-design:
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)

## Examples

``` r
nis <- nis_open(nis_example(2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaLGZww/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaLGZww/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_survey(nis)
older <- dplyr::filter(design, AGE >= 65)
survey::svymean(~LOS, older)
#>       mean     SE
#> LOS 4.5771 0.2929
survey::svyby(~LOS, ~YEAR, older, survey::svymean)
#>      YEAR      LOS        se
#> 2019 2019 4.577143 0.4142243
#> 2020 2020 4.577143 0.4142243
```
