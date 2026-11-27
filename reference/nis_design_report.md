# Report the design and fitted sample for NIS analyses

Reads the sampling metadata retained by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
without querying the original data. Use it on the design after a domain
filter, or on a
[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fit
from that design to see the fitted sample size.

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

A list with the valid-design input years, input and original cohort
counts, design-field exclusions (a discharge can fail multiple fields),
cohort criterion, and current domain count. Weighting fields describe
the base weight column, annualization divisor, and whether supplied
reweights were applied. The PSU and stratum fields name their
year-scoped keys. For a fit, `domain_n` counts the records after any
model subset and before the fit's missing-data action. The `model` entry
gives the fitted unweighted count (`n`, from
[`stats::nobs()`](https://rdrr.io/r/stats/nobs.html)) and the number of
records the fit omitted for missing model data (`excluded_n`).

## Details

Counts describe the input supplied to
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
Filtering that input before making the design can change the sampling
roster. Use a cohort expression or filter the design to restrict a
survey domain. Review the counts for disclosure before sharing them.

## See also

Other survey-design:
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md),
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)

## Examples

``` r
data <- nis_open(nis_example(2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpTs8u0T/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpTs8u0T/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(data, AGE >= 18, keep = c(AGE, LOS), annualize = TRUE)
#> Cohort: 192 discharges; weighted N 114.4; 24 hospitals across 2 years.
nis_design_report(design)
#> $years
#> [1] 2019 2020
#> 
#> $cohort
#> [1] "AGE >= 18"
#> 
#> $input_n
#> [1] 192
#> 
#> $excluded
#> $excluded$total
#> [1] 0
#> 
#> $excluded$by_field
#>        YEAR    HOSP_NIS NIS_STRATUM      DISCWT 
#>           0           0           0           0 
#> 
#> $excluded$by_year
#> # A tibble: 0 × 2
#> # ℹ 2 variables: YEAR <int>, n <dbl>
#> 
#> 
#> $cohort_n
#> [1] 192
#> 
#> $domain_n
#> [1] 192
#> 
#> $weight
#> [1] "DISCWT"
#> 
#> $psu
#> [1] "YEAR"     "HOSP_NIS"
#> 
#> $strata
#> [1] "YEAR"        "NIS_STRATUM"
#> 
#> $nest
#> [1] TRUE
#> 
#> $annualize
#> [1] TRUE
#> 
#> $divisor
#> [1] 2
#> 
#> $reweighted
#> [1] FALSE
#> 
#> $model
#> NULL
#> 
nis_design_report(survey::svyglm(LOS ~ AGE, design = design))
#> $years
#> [1] 2019 2020
#> 
#> $cohort
#> [1] "AGE >= 18"
#> 
#> $input_n
#> [1] 192
#> 
#> $excluded
#> $excluded$total
#> [1] 0
#> 
#> $excluded$by_field
#>        YEAR    HOSP_NIS NIS_STRATUM      DISCWT 
#>           0           0           0           0 
#> 
#> $excluded$by_year
#> # A tibble: 0 × 2
#> # ℹ 2 variables: YEAR <int>, n <dbl>
#> 
#> 
#> $cohort_n
#> [1] 192
#> 
#> $domain_n
#> [1] 192
#> 
#> $weight
#> [1] "DISCWT"
#> 
#> $psu
#> [1] "YEAR"     "HOSP_NIS"
#> 
#> $strata
#> [1] "YEAR"        "NIS_STRATUM"
#> 
#> $nest
#> [1] TRUE
#> 
#> $annualize
#> [1] TRUE
#> 
#> $divisor
#> [1] 2
#> 
#> $reweighted
#> [1] FALSE
#> 
#> $model
#> $model$n
#> [1] 192
#> 
#> $model$excluded_n
#> [1] 0
#> 
#> 
```
