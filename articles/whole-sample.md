# Analyze the whole sample in DuckDB

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

``` r

nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpesmCET/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpesmCET/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
sample <- nis_survey(nis)
older <- filter(sample, AGE >= 65)

survey::svymean(~LOS, older)
#>       mean     SE
#> LOS 4.5771 0.2929
survey::svyby(~LOS, ~YEAR, older, survey::svymean)
#>      YEAR      LOS        se
#> 2019 2019 4.577143 0.4142243
#> 2020 2020 4.577143 0.4142243
```

Use
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)
when your analysis spans a large share of the discharges.
[`filter()`](https://dplyr.tidyverse.org/reference/filter.html) on the
design defines a domain and keeps sampled hospitals in the variance
calculation. Means and totals, including grouped means and totals,
aggregate in DuckDB.

``` r

fit <- survey::svyglm(LOS ~ AGE + factor(YEAR), design = older)
summary(fit)$coefficients
#>                    Estimate Std. Error   t value   Pr(>|t|)
#> (Intercept)      15.2509080 3.07763091  4.955405 0.00014320
#> AGE              -0.1379447 0.03732822 -3.695453 0.00196111
#> factor(YEAR)2020  0.0000000 0.58616423  0.000000 1.00000000
```

Use additive `svyglm()` models with Gaussian identity, binomial or
quasibinomial logit, or Poisson or quasipoisson log families. Use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
for interactions, offsets, survey quantiles, chi-square tests, srvyr
summary verbs, and
[`tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html).

## Estimate an average annual total

``` r

years <- nis |> distinct(YEAR) |> collect()
k <- nrow(years)
annual <- nis_survey(nis, weights = DISCWT / k)
survey::svytotal(~I(AGE >= 65), annual)
#>                   total     SE
#> I(AGE >= 65)FALSE  61.9 1.3778
#> I(AGE >= 65)TRUE   52.5 2.3162
```

Use `k` equal to the number of years with valid design records. The
example has complete coverage. Keep `DISCWT` unscaled for separate
annual totals. [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)
