# Create a lazy whole-sample NIS survey design

Estimate means, totals, and supported survey-weighted models in DuckDB.

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
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
on the design to define a domain while retaining the original sample for
variance. Invalid design fields are excluded when defining the sample.

Use
[`survey::svymean()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
[`survey::svytotal()`](https://rdrr.io/pkg/survey/man/surveysummary.html),
and [`survey::svyby()`](https://rdrr.io/pkg/survey/man/svyby.html) for
summaries.
[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html)
supports additive Gaussian identity, binomial and quasibinomial logit,
and Poisson and quasipoisson log models. Use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
for interactions, offsets, survey quantiles, chi-square tests, or
[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).

The design supports the `"fail"` and `"adjust"` settings of
`survey.lonely.psu` and honors `survey.adjust.domain.lonely`.

## See also

[Analyze the whole sample in
DuckDB](https://msaadasif.github.io/easyNIS/articles/whole-sample.html),
[Analyze the whole sample in
DuckDB](https://msaadasif.github.io/easyNIS/articles/whole-sample.html)

Other survey-design:
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)

## Examples

``` r
nis <- nis_open(nis_example(2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpc9rYtA/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpc9rYtA/duckdb
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
