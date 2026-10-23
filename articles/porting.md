# Porting an existing NIS study to easyNIS

This short guide maps common steps in an existing NIS analysis to
easyNIS. The code below runs on
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
data only. Its diagnosis and procedure slots are replaced with invented
codes so the example does not reproduce a real study definition.

## Replace regular-expression scans with prefix flags

For a regex such as `^A12.*|^B34.*`, use the prefixes `c("A12", "B34")`.
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
checks each diagnosis slot on its own, so codes in adjacent slots cannot
join into a false match. It ignores case, periods, and spaces.
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
does the same for procedure slots. `position = "principal"` checks slot
1; `"secondary"` checks diagnosis slots after slot 1; and `"any"` checks
all available slots.

Prefix lists express literal starts only. A regex that requires a
particular suffix or code length, uses a character class, or allows
optional characters cannot be represented exactly. Keep that condition
in a regular expression with a plain `mutate()`/`if_any()` expression on
the code columns.

The example starts from generated data and substitutes illustrative
codes, then creates diagnosis and procedure flags:

``` r

example_path <- nis_example(years = 2018:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp39M4jT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp39M4jT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp39M4jT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

nis_flagged <- nis_open(example_path, years = 2018:2020) |>
  dplyr::mutate(
    I10_DX1 = dplyr::if_else(AGE >= 50, "A1234", "C004"),
    I10_DX2 = dplyr::if_else(FEMALE == 1, "B34.1", "C00.5"),
    I10_PR1 = dplyr::if_else(FEMALE == 1, "0AB12", "0XY34")
  ) |>
  nis_flag_dx(cohort_dx = c("A12", "B34"), position = "principal") |>
  nis_flag_dx(exposure = "B34", position = "any") |>
  nis_flag_pr(example_procedure = "0AB", position = "any")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp39M4jT/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```

For a regex that needs a suffix test, keep the expression explicit. For
example, this checks for an invented code with exactly two digits after
`A12` in any diagnosis slot:

``` r

nis_flagged <- nis_flagged |>
  dplyr::mutate(
    exact_code = dplyr::coalesce(
      dplyr::if_any(
        dplyr::starts_with("I10_DX"),
        ~ grepl("^A12[0-9]{2}$", as.character(.x))
      ),
      FALSE
    )
  )
```

The prefix and regex paths serve different definitions: use the simpler
prefix flag where the condition is a literal prefix, and retain the
regex where the suffix matters.

## Replace local recode helpers

If a local cleaning helper used `case_when()` to turn known HCUP codes
such as sex, payer, or discharge disposition into labels, remove those
repeated recodes.
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
calls
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
on the collected analysis data. Known value codes become factors and
receive variable labels; unknown values are not given guessed labels.
You can call
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
directly on a collected data frame when you need the same recoding
outside
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

Keep custom study-derived variables in `mutate()`. Set their factor
order explicitly with
[`forcats::fct_relevel()`](https://forcats.tidyverse.org/reference/fct_relevel.html),
and override the displayed label at the table where it is used:

``` r

study_design <- nis_flagged |>
  nis_design(
    cohort = cohort_dx & AGE >= 50,
    keep = c(
      AGE, FEMALE, DIED, LOS, TOTCHG, CCR_NIS,
      cohort_dx, exposure, example_procedure
    ),
    dollars = 2020
  ) |>
  dplyr::mutate(
    exposed = forcats::fct_relevel(
      factor(
        dplyr::if_else(as.character(exposure) == "Yes", "Yes", "No"),
        levels = c("No", "Yes")
      ),
      "No"
    ),
    age_band = forcats::fct_relevel(
      factor(dplyr::if_else(AGE >= 65, "65 or older", "Under 65")),
      "Under 65"
    )
  )
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 201 discharges; weighted N 239.7; 36 hospitals across 3 years.
```

Use `gtsummary` label overrides for derived variables; HCUP labels
already cover the common coded fields:

``` r

table_one <- gtsummary::tbl_svysummary(
  study_design,
  by = exposed,
  include = c(AGE, FEMALE, age_band, DIED, LOS, cost_adj),
  label = list(
    age_band ~ "Illustrative age group",
    cost_adj ~ "Hospital cost in 2020 USD"
  )
)

table_one$table_body |>
  dplyr::select(variable, label) |>
  dplyr::distinct()
#> # A tibble: 10 × 2
#>    variable label                      
#>    <chr>    <chr>                      
#>  1 AGE      Age, years                 
#>  2 FEMALE   Sex of patient             
#>  3 FEMALE   Male                       
#>  4 FEMALE   Female                     
#>  5 age_band Illustrative age group     
#>  6 age_band Under 65                   
#>  7 age_band 65 or older                
#>  8 DIED     Died during hospitalization
#>  9 LOS      Length of stay, days       
#> 10 cost_adj Hospital cost in 2020 USD
```

## Declare the cohort with `nis_design()`

Older scripts may build
[`survey::svydesign()`](https://rdrr.io/pkg/survey/man/svydesign.html)
with `HOSPID` and `TRENDWT`, then call
[`subset()`](https://rdrr.io/r/base/subset.html) for the analysis
cohort. Those fields are not available in current NIS releases. For the
supported ICD-10 years,
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
uses `HOSP_NIS`, `NIS_STRATUM`, and `DISCWT`, and makes hospital and
stratum IDs year-specific before combining years. Pass the cohort
expression and the columns to retain; do not filter to the cohort before
constructing the design.

The design retains one placeholder for each hospital-year with no cohort
discharges. This lets the survey domain retain the sampled hospital
context when estimating the declared cohort. The placeholder-row method
is experimental and should be validated against a full-data design for
the analysis at hand. After
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
filters should only narrow the cohort declared by its `cohort` argument.

## Replace charge adjustment and testing switches

If `adj_TOTCHG` was inflation-adjusted **charges**, its counterpart is
`charges_adj`. `cost_adj` estimates hospital **cost** by multiplying
charges by `CCR_NIS` before inflation adjustment. With `TOTCHG` and
`CCR_NIS` in `keep`, `nis_design(..., dollars = 2020)` creates both
fields, as in the example above. For a collected data frame, call
`nis_cost(data, dollars = 2020)` directly.

Replace a `TESTING` switch that points to a small hand-picked data file
with `nis_example(years = 2018:2020)`. It writes an invented, temporary
dataset with the same broad column shape needed to run the pipeline; it
contains no study records.

The example directory can be removed after use with
`unlink(example_path, recursive = TRUE)`.

## Common pitfalls

> **Common pitfalls**
>
> - Regex expressions may encode suffix rules that a prefix flag cannot
>   reproduce. Review each code-set translation.
> - A pooled analysis needs year-scoped hospital and stratum identifiers
>   and a stated weight convention.
> - Never treat
>   [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
>   results as study or national estimates.

Function references:
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md),
and
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md).
