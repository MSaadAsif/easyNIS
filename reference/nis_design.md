# Prepare a cohort survey design

Collects cohort rows and one zero-domain placeholder per hospital-year
with no cohort discharges, then builds a nested NIS survey design. The
placeholder-row method is experimental and is gated against a full-data
design. After this function returns,
[`filter()`](https://rdrr.io/r/stats/filter.html) may only narrow the
declared cohort; it cannot define a new cohort. Hospital geography
columns are optional. Hospital and stratum identifiers are scoped by
year (`YEAR` + `HOSP_NIS` and `YEAR` + `NIS_STRATUM`), because HCUP
reassigns hospital numbers annually and 2023 stratum codes are
sequential. Costs and charges use `TOTCHG` only, unless `charges` names
another column such as `TOTCHG_2023`; nothing is coalesced silently,
because the 2023 field is not comparable to earlier-year `TOTCHG`. The
2023 layout facts (`TOTCHG_2023`, removed `HOSP_REGION` and
`HOSP_DIVISION`, sequential strata) are UNVERIFIED against official HCUP
2023 documentation and real 2023 data.

## Usage

``` r
nis_design(
  .data,
  cohort,
  keep,
  annualize = FALSE,
  dollars = NULL,
  charges = "TOTCHG"
)
```

## Arguments

- .data:

  Lazy DuckDB query or data frame.

- cohort:

  Logical data-masked cohort expression. Missing values are counted and
  treated as outside the cohort. Only valid-design discharges are
  counted.

- keep:

  Tidyselect expression naming analysis columns to collect.

- annualize:

  Divide discharge weights by the number of distinct `YEAR` values among
  valid-design discharges. A year counts as one whole year however much
  of it is present, so a partial-year era such as the ICD-10 fourth
  quarter of 2015 counts the same as a full year, and a year with no
  cohort discharges still counts. When `DQTR` is present, a warning
  identifies years where the valid-design data has fewer than four
  quarters. A separate warning identifies a cohort limited to the ICD-9
  (Q1-Q3) or ICD-10 (Q4) part of 2015. Exclude partial years or use
  `annualize = FALSE` and apply a suitable fractional-year factor with
  [`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
  if you need a different convention.

- dollars:

  Optional reference dollar year for adjusted costs and charges. When
  supplied, keep `CCR_NIS` and the `charges` column.

- charges:

  Name of the total-charge column used for adjusted costs and charges.
  Defaults to `"TOTCHG"`. Use `"TOTCHG_2023"` for 2023-only analyses, or
  build a pooled column explicitly with
  `dplyr::mutate(TOTCHG = dplyr::coalesce(TOTCHG_2023, TOTCHG))` before
  calling; either choice mixes charge definitions across years.

## Value

A filtered [`srvyr::tbl_svy`](http://gdfe.co/srvyr/reference/tbl_svy.md)
survey design.

## Invalid design fields

Discharges whose `YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT` is
missing, non-finite, or not positive are excluded before the cohort is
applied. HCUP specifies `DISCWT` as the discharge weight, `NIS_STRATUM`
as the stratum, and `HOSP_NIS` as the hospital cluster ([variance
guidance](https://hcup-us.ahrq.gov/reports/methods/2015_09.jsp); [2017
NIS
introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2017.jsp));
HCUP also documents missing and invalid coding conventions ([coding
conventions](https://hcup-us.ahrq.gov/db/coding.jsp)). Records with
invalid values cannot be placed in the documented design as supplied.
Exclusion is not a claim that these records have zero population weight
or that estimates are unbiased. Report the excluded count and affected
fields, and consider whether conclusions could depend on them. The
returned design has a `nis_excluded` attribute containing aggregate
`total`, `by_field`, and `by_year` counts; `by_year` includes years with
exclusions when the year is itself valid. A discharge can fail more than
one field.

The query is scanned twice for design validation and cohort collection.
When annualizing and `DQTR` is present, quarter coverage requires an
additional summary scan. The cohort expression is evaluated once over
the full data.

## See also

[Survey design and
weighting](https://msaadasif.github.io/easyNIS/reference/articles/survey-design.md).

Other survey-design:
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmprPKoF7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 50,
  keep = c(AGE, FEMALE, TOTCHG, CCR_NIS),
  dollars = 2024
)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 72 discharges; weighted N 83.2; 18 hospitals across 2 years.
srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_age = srvyr::survey_mean(AGE)
)
#> # A tibble: 1 × 4
#>   discharges discharges_se mean_age mean_age_se
#>        <dbl>         <dbl>    <dbl>       <dbl>
#> 1       83.2          11.8     69.7       0.607
```
