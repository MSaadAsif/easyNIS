# Prepare a cohort survey design

Build a survey design from the annual sample and the declared cohort.
Use the result with srvyr, survey, and gtsummary.

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

  Lazy DuckDB query or data frame. Existing dplyr groups and rowwise
  grouping are removed before evaluating `cohort`; aggregate cohort
  expressions therefore use the full input, not individual input groups.

- cohort:

  Logical data-masked cohort expression. Missing values are counted and
  treated as outside the cohort. Only valid-design discharges are
  counted. Untyped SQL `NULL` values are accepted as missing logical
  values. Lazy columns are validated using their SQL type; numeric and
  character columns are rejected even when all missing.

- keep:

  Tidyselect expression naming analysis columns to collect. Renaming
  uses the selected source values and labels. Required design fields
  remain under their original names, as do selected cost inputs when
  costs are computed. Aliases cannot overwrite these retained fields or
  computed cost columns. Type predicates inspect actual columns locally
  and a zero-row schema for lazy queries; predicates depending on row
  values are therefore not portable across backends.

- annualize:

  Divide every discharge weight by the number of years with valid design
  records. Each partial year counts as one year.

- dollars:

  Reference dollar year for adjusted charges and costs. To set it, keep
  the charge field and `CCR_NIS`.

- charges:

  Name of the charge field. Defaults to `"TOTCHG"`. Choose the field for
  the years analyzed. See [Years and coding
  eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.html).

## Value

A filtered [`srvyr::tbl_svy`](http://gdfe.co/srvyr/reference/tbl_svy.md)
survey design. The analysis data contains the required design fields,
the columns selected by `keep`, and any computed cost columns.
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
keeps binary indicators logical and converts known multi-level codes to
factors. Use [`stats::weights()`](https://rdrr.io/r/stats/weights.html)
for the survey weights.

## Details

Hospital and stratum identifiers include the year. Hospital-years
without eligible discharges contribute zero to the domain calculation.
Filter the returned design to estimate within a smaller domain. For a
dataset saved with
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md),
omit `cohort`.

## Invalid design fields

The design excludes discharges with missing, non-finite, or nonpositive
`YEAR`, `HOSP_NIS`, `NIS_STRATUM`, or `DISCWT`. Inspect the excluded
counts by field and year with
[`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md).

## Adjusted charges and costs

Keeping both the charge field and `CCR_NIS` adds `charges_adj` and
`cost_adj`. The default dollar year is the latest included design year.
Set `dollars` to use another reference year.

## See also

[Make tables and fit survey
models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html),
[Make tables and fit survey
models](https://msaadasif.github.io/easyNIS/articles/tables-and-models.html).

Other survey-design:
[`nis_design_report()`](https://msaadasif.github.io/easyNIS/reference/nis_design_report.md),
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md),
[`nis_survey()`](https://msaadasif.github.io/easyNIS/reference/nis_survey.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwxUhgt/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpwxUhgt/duckdb
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
#> Preparing the cohort survey design.
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
