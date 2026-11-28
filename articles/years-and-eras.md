# Years and coding eras

``` r

library(easyNIS)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
library(srvyr)
#> 
#> Attaching package: 'srvyr'
#> The following object is masked from 'package:stats':
#> 
#>     filter

nis <- nis_open(nis_example(years = 2015))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpozLwRt/duckdb
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
#> ℹ /tmp/RtmpozLwRt/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> This message is displayed once per session.
nis_audit_code_transition(
  nis, codes = c(heart_failure = "I50"), type = "dx", system = "icd10",
  by = c(YEAR, DQTR)
)
#> # A tibble: 4 × 8
#>    YEAR  DQTR code_group    n_cohort_unweighted n_unweighted n_weighted
#>   <int> <int> <chr>                       <int>        <int>      <dbl>
#> 1  2015     1 heart_failure                  24            0        0  
#> 2  2015     2 heart_failure                  24            0        0  
#> 3  2015     3 heart_failure                  24            0        0  
#> 4  2015     4 heart_failure                  24           18       20.8
#> # ℹ 2 more variables: pct_within_year <dbl>, yoy_pct_change <dbl>
nis_audit_dx_position(nis, "I50", system = "icd10", outcomes = DIED)
#> # A tibble: 3 × 7
#>   presentation n_unweighted n_weighted pct_of_any_unweighted pct_of_any_weighted
#>   <chr>               <dbl>      <dbl>                 <dbl>               <dbl>
#> 1 principal              18       20.8                   100                 100
#> 2 secondary_o…            0        0                       0                   0
#> 3 any                    18       20.8                   100                 100
#> # ℹ 2 more variables: DIED_rate_unweighted <dbl>, DIED_rate_weighted <dbl>
```

The examples use invented data. The transition audit counts matches by
quarter in the ICD-10 diagnosis slots. Use a separate audit with
`system = "icd9"` and the corresponding ICD-9 prefixes for earlier
quarters. The position audit compares principal, secondary-only, and
any-position definitions. Both give descriptive counts or rates. Use a
survey design for standard errors.

## The 2012 redesign

Starting in 2012, the NIS samples discharges across hospitals in its
sampling frame. Earlier releases sampled hospitals and retained their
discharges. For a trend spanning the redesign, HCUP supplies `TRENDWT`
for the applicable pre-2012 data. Use `DISCWT` from 2012 onward. easyNIS
handles 2012 and later and does not apply historical trend weights.
[HCUP trend weight
guidance](https://hcup-us.ahrq.gov/db/nation/nis/trendwghts.jsp)

## The October 2015 coding change

Quarters 1 through 3 of 2015 use ICD-9-CM. Quarter 4 uses ICD-10-CM for
diagnoses and ICD-10-PCS for procedures. Specify separate code sets for
the two systems. `system = "both"` requires separate ICD-9 and ICD-10
slots. Review matches by quarter before interpreting a change in
prevalence. [HCUP NIS
documentation](https://hcup-us.ahrq.gov/db/nation/nis/nisdbdocumentation.jsp)

## Quarter coverage

Aggregate by `YEAR` and `DQTR` to see which quarters contribute. With
`DQTR` available,
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
flags incomplete coverage during annualization and identifies a cohort
restricted to one 2015 coding era. The annualization divisor counts a
partial year once. Report a quarter-specific or era-specific estimate as
such.

## The 2023 and 2024 Core layouts

The package uses the Core layouts from the HCUP SAS load programs.
`TOTCHG_2023` and `TOTCHG_2024` are separate from the earlier `TOTCHG`
field. Select the charge field for the year you analyze and check
comparability before combining fields. The package layouts for these
years have been checked against the load programs. Conversion on
licensed annual files for these layouts has yet to be verified. [HCUP
NIS load programs](https://hcup-us.ahrq.gov/db/nation/sasloadprog.jsp)

## Annual links for companions and cost-to-charge ratios

Join the Hospital file by `YEAR` and `HOSP_NIS` and the Severity file by
`YEAR` and `KEY_NIS`. Obtain the matching [HCUP cost-to-charge ratio
file](https://hcup-us.ahrq.gov/db/ccr/ip-ccr/ip-ccr.jsp) for each data
year. Prepare it with the hospital key in its release documentation,
then link by `YEAR` and `HOSP_NIS`. Check which years and hospitals lack
a match.
