# Defining cohorts

## Flag diagnoses and procedures

The analyst supplies literal code prefixes. Each slot is tested
separately; punctuation, spaces, and case in the supplied prefixes are
normalized.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50") |>
  nis_flag_dx(principal_hf = "I50", position = "principal") |>
  nis_flag_pr(ablation = "02L")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(heart_failure, principal_hf, ablation) |> dplyr::collect()
#> # A tibble: 3 × 4
#>   heart_failure principal_hf ablation     n
#>   <lgl>         <lgl>        <lgl>    <dbl>
#> 1 FALSE         FALSE        FALSE       36
#> 2 TRUE          TRUE         FALSE      108
#> 3 FALSE         FALSE        TRUE        48
```

The table shows synthetic discharge counts for each flag combination. To
make a principal-only diagnosis flag, call
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
with `position = "principal"`; use `"secondary"` for slots after the
principal one.
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
supports `"any"` and `"principal"`.

Supply several named definitions in one call when they share the same
`position` and `system`. For example, use
`nis_flag_dx(nis, heart_failure = "I50", hypertension = "I10")` to add
both flags to the same DuckDB projection.

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
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md)
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
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
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
#> Preparing the cohort survey design.
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

## Record eligibility across the 2015 transition

Supply named code criteria in `.codes` to use the same definitions for
eligibility and the transition audit. The code criteria run in list
order after the logical criteria in `...`. Here the first code step
finds a match in any diagnosis slot and the second requires a principal
match. These definitions illustrate the workflow on invented data.

``` r

nis <- nis_open(nis_example(years = 2015))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Experimental: years before 2016 store ICD-9-CM codes in DX1, PR1, ... slots.
#> ℹ Flag them with `system = "icd9"`; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4)
#>   slots.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
prefixes <- list(icd9 = c("123", "12345", "V0001"), icd10 = c("I50", "Z515"))
flow <- nis_attrition(
  nis,
  adults = AGE >= 18,
  .codes = list(
    matching_dx = list(type = "dx", system = "both", position = "any", codes = prefixes),
    principal_dx = list(type = "dx", system = "both", position = "principal", codes = prefixes)
  ),
  .design = TRUE
)
flow
#> # A tibble: 4 × 7
#>    step criterion               n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                          <int>                <int>      <dbl>
#> 1     0 Valid design discharges           96                   NA      114. 
#> 2     1 adults                            96                    0      114. 
#> 3     2 matching_dx                       91                    5      108. 
#> 4     3 principal_dx                      54                   37       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
attr(flow, "nis_criteria")
#> # A tibble: 3 × 5
#>   criterion    type  position  system codes           
#>   <chr>        <chr> <chr>     <chr>  <list>          
#> 1 adults       NA    NA        NA     <NULL>          
#> 2 matching_dx  dx    any       both   <named list [2]>
#> 3 principal_dx dx    principal both   <named list [2]>

design <- nis_design(nis, cohort = !!nis_attrition_cohort(flow), keep = c(AGE, LOS))
#> Preparing the cohort survey design.
fit <- survey::svyglm(LOS ~ AGE, design = design)
stats::nobs(fit)
#> [1] 54
```

The criteria table records the system and slot rule for Methods. Here
the last attrition count equals the number of observations in the model
because `AGE` and `LOS` are complete among eligible discharges. See the
[quarterly audit of these
criteria](https://msaadasif.github.io/easyNIS/articles/code-transitions.html#reuse-cohort-criteria).

## Save a cohort for another session

Pass the full lazy sample and the eligibility rule to
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md).
Keep the columns you expect to use in later analyses. The writer creates
a new directory with yearly Parquet parts and saves the eligibility
expression, source years, and easyNIS version in each part’s metadata.

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
path <- nis_write_cohort(nis, heart_failure & AGE >= 50, tempfile(),
                         keep = c(AGE, LOS))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

# In a later session
design <- nis_design(nis_open(path), keep = c(AGE, LOS), annualize = TRUE)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaRTyzo/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Preparing the cohort survey design.
design |>
  dplyr::filter(AGE >= 65) |>
  dplyr::summarise(discharges = srvyr::survey_total())
#> # A tibble: 1 × 2
#>   discharges discharges_se
#>        <dbl>         <dbl>
#> 1       25.2          3.57
```

The saved cohort carries one placeholder per sampled hospital-year with
no eligible discharge. This preserves the survey variance structure,
including whole strata and years where the cohort is empty.
Annualization still uses all years with valid design records. Keep the
original design run if you need its invalid-design exclusion counts or
full-sample quarter coverage.

Apply additional patient filters to the survey design after reopening.
When inspecting raw Parquet rows, use `dplyr::filter(.in_cohort)` before
counting discharges. To re-save a cohort with fewer columns, pass its
reopened query to
[`nis_write_cohort()`](https://msaadasif.github.io/easyNIS/reference/nis_write_cohort.md)
and omit `cohort`. To change the eligibility rule, return to the source
sample.

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
[`nis_audit_prday()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_prday.md).
