# Porting an existing NIS study to easyNIS

This short guide maps common steps in an existing NIS analysis to
easyNIS. The examples use invented discharges, including records from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
with illustrative diagnosis and procedure codes.

## Match each code slot separately

A legacy scan that pastes slots together can match a code that never
occurs in any slot. This invented record splits `A123` across two
diagnoses.

``` r

split_slots <- data.frame(I10_DX1 = "A1", I10_DX2 = "234")
with(split_slots, grepl("A123", paste0(I10_DX1, I10_DX2)))
#> [1] TRUE
nis_flag_dx(split_slots, eligible = "A123")$eligible
#> [1] FALSE
```

For patterns such as `^A12.*|^B34.*`, use the prefixes
`c("A12", "B34")`.
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
checks each diagnosis slot on its own.
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
does the same for procedure slots. Set `position = "principal"` to check
slot 1, `"secondary"` to check later diagnosis slots, or `"any"` to
check all available slots. Prefix arguments are normalized by removing
periods and spaces and converting to uppercase. Slot values are compared
as stored.

The example starts from generated data and substitutes illustrative
codes, then creates diagnosis and procedure flags:

``` r

example_path <- nis_example(years = 2018:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpdkWrqn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

nis_flagged <- nis_open(example_path, years = 2018:2020) |>
  dplyr::mutate(
    I10_DX1 = dplyr::if_else(AGE >= 50, "A1234", "A12345"),
    I10_DX2 = dplyr::if_else(FEMALE == 1, "B341", "C005"),
    I10_PR1 = dplyr::if_else(FEMALE == 1, "0AB12", "0XY34")
  ) |>
  nis_flag_dx(cohort_dx = c("A12", "B34"), position = "principal") |>
  nis_flag_dx(exposure = "B34", position = "any") |>
  nis_flag_pr(example_procedure = "0AB", position = "any")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpdkWrqn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```

Use a regex definition when the legacy rule constrains the rest of the
code. This example requires exactly two digits after `A12` in a
diagnosis slot. Both principal codes match the prefix, while only
`A1234` matches the regex.

``` r

nis_flagged <- nis_flagged |>
  nis_flag_dx(eligible = list(regex = "A12[0-9]{2}"), position = "any")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpdkWrqn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

nis_flagged |>
  dplyr::distinct(I10_DX1, cohort_dx, eligible) |>
  dplyr::collect()
#> # A tibble: 2 × 3
#>   I10_DX1 cohort_dx eligible
#>   <chr>   <lgl>     <lgl>   
#> 1 A12345  TRUE      FALSE   
#> 2 A1234   TRUE      TRUE
```

Regex definitions match the whole stored slot, so outer `^` and `$`
anchors are optional. A legacy regex that intentionally matched only
part of a code needs an explicit pattern for the rest of the slot, such
as a trailing `.*` for an unconstrained suffix. Write case-sensitive
patterns for the stored uppercase, undotted NIS codes. The package
passes regex patterns through without the normalization applied to
literal prefixes.

## Replace local recode helpers

If a local cleaning helper used `case_when()` to turn known HCUP codes
such as sex, payer, or discharge disposition into labels, remove those
repeated recodes.
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
calls
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md)
on the collected analysis data. Known binary codes become logical, and
multi-level codes become factors. Both receive variable labels. You can
call
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
    age_band = forcats::fct_relevel(
      factor(dplyr::if_else(AGE >= 65, "65 or older", "Under 65")),
      "Under 65"
    )
  )
#> Preparing the cohort survey design.
```

Use `gtsummary` label overrides for derived variables; HCUP labels
already cover the common coded fields:

``` r

table_one <- gtsummary::tbl_svysummary(
  study_design,
  by = exposure,
  include = c(AGE, FEMALE, age_band, DIED, LOS, cost_adj),
  label = list(
    FEMALE ~ "Female",
    age_band ~ "Illustrative age group",
    cost_adj ~ "Hospital cost in 2020 USD"
  )
)

table_one$table_body |>
  dplyr::select(variable, label) |>
  dplyr::distinct()
#> # A tibble: 8 × 2
#>   variable label                      
#>   <chr>    <chr>                      
#> 1 AGE      Age, years                 
#> 2 FEMALE   Female                     
#> 3 age_band Illustrative age group     
#> 4 age_band Under 65                   
#> 5 age_band 65 or older                
#> 6 DIED     Died during hospitalization
#> 7 LOS      Length of stay, days       
#> 8 cost_adj Hospital cost in 2020 USD
```

## Keep discharge disposition and mortality separate

Check source values alongside the derived outcomes and the displayed
disposition label before carrying over a legacy recode.

``` r

outcomes <- nis_outcomes(data.frame(DIED = 1L, LOS = 2L, DISPUNIFORM = 6L))
outcomes[c("DIED", "DISPUNIFORM", "in_hospital_death", "discharge_disposition")]
#>   DIED DISPUNIFORM in_hospital_death discharge_disposition
#> 1    1           6              TRUE                     6
as.character(nis_label(outcomes)$discharge_disposition)
#> [1] "Home health care"
```

This invented row has an in-hospital death flag and a disposition label
of “Home health care.” Check inconsistent pairs against the source-year
coding and keep a documented rule for handling them. Use
`in_hospital_death` for mortality and `discharge_disposition` for
destination. See [Hospitalization
outcomes](https://msaadasif.github.io/easyNIS/articles/articles/outcomes.md).

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
