# Add standard discharge outcomes

Derive in-hospital mortality, length of stay, and discharge disposition
from the numeric NIS Core fields. Each outcome uses its own source
field. Missing or unrecognized codes become `NA`, including negative
HCUP sentinels and non-integer values.

## Usage

``` r
nis_outcomes(.data)
```

## Arguments

- .data:

  A data frame or lazy DuckDB table with numeric `DIED`, `LOS`, and
  `DISPUNIFORM` fields. Apply this before converting the fields to
  labels.

## Value

The input with three columns added or replaced:

- `in_hospital_death`: 0 for discharge alive and 1 for in-hospital death
  from `DIED`.

- `los_days`: elapsed days from `LOS`, including zero for same-day
  stays. Values outside the HCUP inpatient range of 0 to 365 whole days
  become missing.

- `discharge_disposition`: character labels from `DISPUNIFORM` using the
  same labels as
  [`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md).
  Codes 1, 2, 5, 6, 7, and 20 distinguish routine home/self-care,
  short-term hospital transfer, other facility transfer, home health
  care, discharge against medical advice, and in-hospital death. Codes
  21 (court/law enforcement) and 99 (alive, destination unknown) retain
  their own labels.

For a lazy DuckDB input, the result is a lazy query.

## See also

[Hospitalization
outcomes](https://msaadasif.github.io/easyNIS/reference/articles/outcomes.md),
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)

## Examples

``` r
nis_open(nis_example(years = 2024)) |>
  nis_outcomes() |>
  dplyr::count(discharge_disposition) |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpnbck9k/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpnbck9k/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 8 × 2
#>   discharge_disposition                                       n
#>   <chr>                                                   <dbl>
#> 1 Routine discharge to home/self-care                        12
#> 2 Transfer to another short-term hospital                    12
#> 3 Transfer to SNF, intermediate care, or another facility    12
#> 4 Home health care                                           12
#> 5 Discharged/transferred to court/law enforcement            12
#> 6 Alive, destination unknown                                 12
#> 7 Left against medical advice                                12
#> 8 Died in hospital                                           12
```
