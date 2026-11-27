# Define and save a cohort

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented discharges. A code slot is a numbered column
that holds one diagnosis or procedure code.

## Match diagnosis and procedure codes

``` r

nis <- nis_open(nis_example(years = 2019:2020)) |>
  nis_flag_dx(
    heart_failure = list(regex = "I50[0-9]+", exclude = "I509")
  ) |>
  nis_flag_dx(principal_hf = "I50", position = "principal") |>
  nis_flag_pr(pci = "0270")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

nis |> count(heart_failure, principal_hf, pci) |> collect()
#> # A tibble: 4 × 4
#>   heart_failure principal_hf pci       n
#>   <lgl>         <lgl>        <lgl> <dbl>
#> 1 TRUE          TRUE         TRUE     54
#> 2 FALSE         FALSE        FALSE    42
#> 3 TRUE          TRUE         FALSE    54
#> 4 FALSE         FALSE        TRUE     42
```

The default position checks all slots. Use `position = "principal"` for
slot 1. A string such as `"I50"` matches a prefix. A `regex` matches the
whole stored code. If you supply both, either can set the flag.
Exclusions apply to individual matching codes, so another slot can still
set the flag.

``` r

mixed <- nis_open(nis_example(years = 2014:2016)) |>
  mutate(DX1 = if_else(
    (YEAR == 2014 | (YEAR == 2015 & DQTR < 4)) & HOSP_NIS %% 2L == 0L,
    "4280", DX1
  )) |>
  nis_flag_dx(hf = list(icd9 = "428", icd10 = "I50"), system = "both")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
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
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

mixed |> filter(YEAR == 2015) |> count(DQTR, hf) |> arrange(DQTR, hf) |> collect()
#> # A tibble: 8 × 3
#>    DQTR hf        n
#>   <int> <lgl> <dbl>
#> 1     1 FALSE    12
#> 2     1 TRUE     12
#> 3     2 FALSE    12
#> 4     2 TRUE     12
#> 5     3 FALSE    12
#> 6     3 TRUE     12
#> 7     4 FALSE     6
#> 8     4 TRUE     18
nis_attrition(mixed, adult = AGE >= 18, hf = hf, by_year = TRUE, .design = TRUE)
#> # A tibble: 9 × 8
#>    YEAR  step criterion             n_unweighted n_dropped_unweighted n_weighted
#>   <int> <int> <chr>                        <int>                <int>      <dbl>
#> 1  2014     0 Valid design dischar…           96                   NA      114. 
#> 2  2014     1 adult                           96                    0      114. 
#> 3  2014     2 hf                              48                   48       57.6
#> 4  2015     0 Valid design dischar…           96                   NA      114. 
#> 5  2015     1 adult                           96                    0      114. 
#> 6  2015     2 hf                              54                   42       64  
#> 7  2016     0 Valid design dischar…           96                   NA      114. 
#> 8  2016     1 adult                           96                    0      114. 
#> 9  2016     2 hf                              54                   42       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
```

Supply separate definitions for each system when the source contains
both slot sets. The example adds invented ICD-9 matches so you can see
both systems in the quarter audit and follow eligibility counts across
all three years. Check how your own code sets behave around the
transition. [Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)

## Use CCSR categories or procedure days

The Clinical Classifications Software Refined (CCSR) groups ICD-10 codes
into clinical categories.

``` r

nis |>
  nis_add_ccsr(position = "default", version = "2025.1") |>
  count(ccsr) |>
  collect()
#> # A tibble: 2 × 2
#>   ccsr       n
#>   <chr>  <dbl>
#> 1 CIR019   108
#> 2 RSP002    84

timing <- nis |> mutate(PRDAY1 = 0L, PRDAY2 = 1L)
nis_audit_prday(timing, pr = "0270")
#> # A tibble: 50 × 8
#>     YEAR  slot matched_slots known_day missing_day sentinel_invalid_day
#>    <int> <int>         <int>     <int>       <int>                <int>
#>  1  2019     1            48        48           0                    0
#>  2  2019     2             0         0           0                    0
#>  3  2019     3             0         0           0                    0
#>  4  2019     4             0         0           0                    0
#>  5  2019     5             0         0           0                    0
#>  6  2019     6             0         0           0                    0
#>  7  2019     7             0         0           0                    0
#>  8  2019     8             0         0           0                    0
#>  9  2019     9             0         0           0                    0
#> 10  2019    10             0         0           0                    0
#> # ℹ 40 more rows
#> # ℹ 2 more variables: absent_prday_column <int>, pct_known <dbl>
timing |>
  nis_flag_pr_timing(
    index_pr = list(prefix = "0270", exclude = "02703DZ"),
    outcome_pr = list(regex = "02L73.*"),
    relation = "after", missing_day = "indeterminate"
  ) |>
  count(outcome_post_index) |>
  collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 2 × 2
#>   outcome_post_index     n
#>   <lgl>              <dbl>
#> 1 FALSE                168
#> 2 TRUE                  24
```

The bundled v2025.1 mappings can keep the same definitions across study
years. `position = "default"` returns one inpatient category for the
principal diagnosis. The example supplies invented procedure days.
Timing uses the earliest known index day and accepts the same prefixes,
full-code regular expressions, and exact exclusions as
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md).
For `system = "both"`, supply named `icd9` and `icd10` definitions for
each procedure. Timing compares slots within the same code system. Audit
procedure-day availability before interpreting an order.

## Count eligibility steps and save the cohort

``` r

flow <- nis_attrition(
  nis, adult = AGE >= 18, hf = heart_failure, by_year = TRUE, .design = TRUE
)
flow
#> # A tibble: 6 × 8
#>    YEAR  step criterion             n_unweighted n_dropped_unweighted n_weighted
#>   <int> <int> <chr>                        <int>                <int>      <dbl>
#> 1  2020     0 Valid design dischar…           96                   NA      114. 
#> 2  2020     1 adult                           96                    0      114. 
#> 3  2020     2 hf                              54                   42       62.4
#> 4  2019     0 Valid design dischar…           96                   NA      114. 
#> 5  2019     1 adult                           96                    0      114. 
#> 6  2019     2 hf                              54                   42       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>

eligible <- nis_attrition_cohort(flow)
export <- nis |> mutate(stayDays = LOS)
path <- nis_write_cohort(export, !!eligible, tempfile(), keep = c(AGE, stayDays))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis_open(path), keep = stayDays)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp1mjvdW/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Preparing the cohort survey design.
summarise(design, total = survey_total(), mean_stay = survey_mean(stayDays))
#> # A tibble: 1 × 4
#>   total total_se mean_stay mean_stay_se
#>   <dbl>    <dbl>     <dbl>        <dbl>
#> 1  125.     17.3      5.66        0.229
```

The flow counts remaining discharges after each criterion. The saved
Parquet cohort retains the hospital structure used for variance. Open it
without supplying a new `cohort` to
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
Derived names such as `stayDays` keep their spelling when you reopen the
saved cohort. Keep the code that defined your flags with the study.
