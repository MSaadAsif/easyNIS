# Defining cohorts

## Flag diagnoses and procedures

The analyst supplies literal code prefixes. Each slot is tested
separately; punctuation, spaces, and case in the supplied prefixes are
normalized.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50", principal_hf = "I50",
              position = "any") |>
  nis_flag_pr(ablation = "02L")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4T3bKH/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4T3bKH/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(heart_failure, ablation) |> dplyr::collect()
#> # A tibble: 3 × 3
#>   heart_failure ablation     n
#>   <lgl>         <lgl>    <dbl>
#> 1 FALSE         FALSE       36
#> 2 TRUE          FALSE      108
#> 3 FALSE         TRUE        48
```

The table shows synthetic discharge counts for each flag combination. To
make a principal-only diagnosis flag, call
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
with `position = "principal"`; use `"secondary"` for slots after the
principal one.
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
supports `"any"` and `"principal"`.

## Classify diagnoses and procedures with CCSR

[`nis_add_ccsr()`](https://msaadasif.github.io/easyNIS/reference/nis_add_ccsr.md)
matches complete ICD-10 codes to the bundled AHRQ mappings in DuckDB. An
any-slot search returns a list of distinct categories for each
discharge. Supply `categories` to keep only the categories relevant to
the study. For a mutually exclusive grouping by principal diagnosis, use
`position = "default"` to return the inpatient default category.

``` r

nis |>
  nis_add_ccsr(categories = "CIR019", name = "hf_categories") |>
  nis_add_ccsr(position = "default", name = "principal_ccsr") |>
  dplyr::filter(length(hf_categories) > 0L) |>
  dplyr::count(principal_ccsr) |>
  dplyr::collect()
#> # A tibble: 1 × 2
#>   principal_ccsr     n
#>   <chr>          <dbl>
#> 1 CIR019           108
```

Use `type = "pr"` for procedures. The default release selection covers
Q4 2015 and calendar years 2016–2024 with the bundled v2025.1. ICD-9 and
years outside the bundled coverage yield missing results. Pin
`version = "2025.1"` to use the same definitions across years and to
include Q1–Q3 2025 if `DQTR` is present. Report the CCSR version in the
study methods. [Agency for Healthcare Research and Quality, Healthcare
Cost and Utilization Project. Clinical Classifications Software Refined
(CCSR), v2025.1, November
2024.](https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccsr_archive.jsp)

## Add procedure timing

Procedure timing compares matching procedure slots with the
corresponding `PRDAY` fields. This small invented data frame makes the
slot relationship visible.

``` r

toy <- data.frame(
  I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ"),
  I10_PR2 = c("0JH604Z", "0JH604Z", "0JH604Z"),
  PRDAY1 = c(0L, 2L, 0L), PRDAY2 = c(1L, 1L, NA_integer_)
)
nis_flag_pr_timing(toy, "02UG0", "0JH60", relation = "after")
#>   I10_PR1 I10_PR2 PRDAY1 PRDAY2 outcome_post_index
#> 1 02UG0JZ 0JH604Z      0      1               TRUE
#> 2 02UG0JZ 0JH604Z      2      1              FALSE
#> 3 02UG0JZ 0JH604Z      0     NA              FALSE
```

The flag is true when an outcome procedure is documented after the
earliest index procedure. Missing or sentinel days need an explicit
`missing_day` policy.
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)
summarizes how often matching slots have a known day.

## Count cohort steps

Define the eligibility rules once in
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md).
With `.design = TRUE`, the baseline includes discharges with valid
survey design fields. Missing criterion values exclude discharges at
that step. Inject the combined rule with `!!nis_attrition_cohort(flow)`
to use the same eligibility criteria in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4T3bKH/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4T3bKH/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
flow <- nis_attrition(
  nis, adults = AGE >= 18, heart_failure = heart_failure, .design = TRUE
)
flow
#> # A tibble: 3 × 7
#>    step criterion               n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                          <int>                <int>      <dbl>
#> 1     0 Valid design discharges           96                   NA      114. 
#> 2     1 adults                            96                    0      114. 
#> 3     2 heart_failure                     54                   42       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>

design <- nis_design(nis, cohort = !!nis_attrition_cohort(flow), keep = LOS)
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
dplyr::summarise(design, discharges = srvyr::unweighted(dplyr::n()))
#> # A tibble: 1 × 1
#>   discharges
#>        <int>
#> 1         54
```

Pass the same input to both calls so the last unweighted attrition count
is the survey domain denominator. The design retains the sampling
structure of hospital-years with zero eligible discharges. Leave
`.design` at its default when the attrition table should start with
every discharge in the input. For alternate diagnosis positions and
changes over time, see [Code transitions and
sensitivity](https://msaadasif.github.io/easyNIS/articles/code-transitions.md).

## Common pitfalls

> **Common pitfalls**
>
> - A prefix is not a validated clinical code set. Define, document, and
>   review it for the study question.
> - A cross-year definition may span different code systems. Do not
>   assume code counts are comparable across the 2015 transition.
> - Unknown procedure days are not equivalent to day zero; choose and
>   report a missing-day policy.

Reference pages:
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md).
