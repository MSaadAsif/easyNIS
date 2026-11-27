# Create a lazy whole-sample NIS survey design

The nested, one-stage Taylor design uses hospital-year PSUs (YEAR ×
HOSP_NIS) and year-specific strata (YEAR × NIS_STRATUM), without a
finite population correction. It uses the valid-design discharges in the
input query. Apply eligibility restrictions with
[`subset()`](https://rdrr.io/r/base/subset.html) or
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
on the design so hospitals outside the domain still contribute to
variance. A query filtered before construction defines a different
sample.

## Usage

``` r
nis_survey(query, weights = DISCWT)
```

## Arguments

- query:

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
one-sided formulas. Grouped estimates support means and totals. DuckDB
computes weighted sums by PSU without collecting discharge records. The
analysis supports the `"fail"` and `"adjust"` values of
`survey.lonely.psu` and honors `survey.adjust.domain.lonely`. Use
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
for row-level survey operations and descriptive tables.

Discharges with missing, non-finite, or nonpositive design fields
(`YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT`) are excluded. Custom
analysis weights must be positive and finite within the domain.

## See also

Other survey-design:
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)

## Examples

``` r
design <- nis_survey(nis_open(nis_example(2019:2020)))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpq6TGTC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpq6TGTC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
survey::svymean(~LOS, subset(design, AGE >= 65))
#>       mean     SE
#> LOS 4.5771 0.2929
survey::svyby(~LOS, ~YEAR, design, survey::svymean)
#>      YEAR      LOS        se
#> 2019 2019 5.534965 0.1975326
#> 2020 2020 5.534965 0.1975326
```
