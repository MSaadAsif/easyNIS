# Port a discharge analysis to easyNIS

``` r

library(easyNIS)
library(dplyr)
library(srvyr)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
```

The examples use invented data.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  select(nis_vars_design(), nis_vars_dx(), AGE, LOS, DIED)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

design <- nis |>
  nis_flag_dx(heart_failure = "I509") |>
  nis_design(cohort = AGE >= 18 & heart_failure, keep = c(AGE, LOS, DIED))
#> Preparing the cohort survey design.

summarise(design, discharges = survey_total(), mean_los = survey_mean(LOS))
#> # A tibble: 1 × 4
#>   discharges discharges_se mean_los mean_los_se
#>        <dbl>         <dbl>    <dbl>       <dbl>
#> 1       26.5          5.47     4.92       0.562
```

Use the full annual input when building the design. Move eligibility
conditions from your row filter to `cohort`. Retain `YEAR`, `HOSP_NIS`,
`NIS_STRATUM`, and `DISCWT` with the analysis columns.

## Match within diagnosis slots

``` r

discharges <- nis |>
  select(I10_DX1, I10_DX2) |>
  head(3) |>
  collect() |>
  mutate(I10_DX1 = c("I50", "I509", "E119"),
         I10_DX2 = c("9", "E119", "I5022"))

discharges |>
  mutate(legacy = grepl("I509", paste0(I10_DX1, I10_DX2), fixed = TRUE)) |>
  nis_flag_dx(exact = list(regex = "I509"),
              substring = list(regex = ".*50.*"))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 3 × 5
#>   I10_DX1 I10_DX2 legacy exact substring
#>   <chr>   <chr>   <lgl>  <lgl> <lgl>    
#> 1 I50     9       TRUE   FALSE TRUE     
#> 2 I509    E119    TRUE   TRUE  TRUE     
#> 3 E119    I5022   FALSE  FALSE TRUE
```

`I509` appears on the first row only after the two slots are pasted
together. An exact code pattern checks each slot separately. A substring
pattern needs `.*` on either side of the text you want to match. Compare
counts before adopting the new definition. If several legacy category
rules match one discharge, keep their original precedence when you
recode.

## Switch systems when both layouts are present

``` r

transition <- nis_open(nis_example(2015)) |>
  mutate(DX1 = if_else(DQTR < 4 & HOSP_NIS %% 2L == 0L, "4280", DX1),
         I10_DX1 = if_else(DQTR == 4 & HOSP_NIS %% 2L == 0L, "I509", I10_DX1))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
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
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
slots <- colnames(transition)
c(icd9 = "DX1" %in% slots, icd10 = "I10_DX1" %in% slots)
#>  icd9 icd10 
#>  TRUE  TRUE

transition |>
  nis_flag_dx(hf = list(icd9 = "4280", icd10 = "I509"), system = "both") |>
  count(DQTR, hf) |>
  collect()
#> # A tibble: 8 × 3
#>    DQTR hf        n
#>   <int> <lgl> <dbl>
#> 1     2 FALSE    12
#> 2     3 TRUE     12
#> 3     1 FALSE    12
#> 4     4 TRUE     12
#> 5     3 FALSE    12
#> 6     2 TRUE     12
#> 7     4 FALSE    12
#> 8     1 TRUE     12

q4 <- transition |> filter(DQTR == 4) |> select(-matches("^DX[0-9]+$"))
q4 |>
  nis_flag_dx(hf = "I509", system = "icd10") |>
  count(hf) |>
  collect()
#> # A tibble: 2 × 2
#>   hf        n
#>   <lgl> <dbl>
#> 1 FALSE    12
#> 2 TRUE     12
```

Use `system = "both"` when the query contains separate ICD-9 and ICD-10
slots. Use `system = "icd10"` for an extract with only ICD-10 slots.
[Years and coding
eras](https://msaadasif.github.io/easyNIS/articles/years-and-eras.md)

## Recode on the appropriate side of the survey design

``` r

source <- nis_open(nis_example(2019)) |>
  mutate(payer_code = PAY1)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmplZ4HDZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

recoded <- nis_design(source, AGE >= 18, keep = c(PAY1, payer_code)) |>
  mutate(payer_group = case_when(
    PAY1 %in% c("Medicare", "Medicaid") ~ "Public",
    !is.na(PAY1) ~ "Other known payer",
    TRUE ~ NA_character_
  ))
#> Preparing the cohort survey design.
recoded$variables |> select(payer_code, PAY1, payer_group) |> head()
#> # A tibble: 6 × 3
#>   payer_code PAY1                  payer_group      
#>        <int> <fct>                 <chr>            
#> 1          3 Private including HMO Other known payer
#> 2          4 Self-pay              Other known payer
#> 3          5 No charge             Other known payer
#> 4          6 Other                 Other known payer
#> 5          1 Medicare              Public           
#> 6          2 Medicaid              Public
```

Copy a raw field to a new name while the query is still in DuckDB.
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
labels the recognized `PAY1` field. Use those labels in the study recode
after the design is in R. Keep the raw code when reconciling results
against the original extract.

## Match the original definition before comparing estimates

| In the original analysis | In easyNIS |
|----|----|
| Principal diagnosis only | `nis_flag_dx(position = "principal")` |
| Exact code `I509` | `list(regex = "^I509$")` |
| ICD-9-CM `4280` and ICD-10-CM `I509` | Separate code sets with `system = "both"` |
| Weighted count | [`survey_total()`](http://gdfe.co/srvyr/reference/survey_total.md) |
| Sampled count | `unweighted(n())` |

Compare eligibility counts, the original and revised weights, and the
standard errors. A matching weighted total can hide a difference in how
the design handles hospitals with no cases. [How the NIS survey design
works](https://msaadasif.github.io/easyNIS/articles/nis-design.md)

Compare the billed amount, adjusted charge, and estimated cost
separately when porting a cost outcome. Record the source charge field,
cost-to-charge ratio, CPI series, and reference dollar year before
comparing the two analyses. [Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.md)
