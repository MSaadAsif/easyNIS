# Hospitalization outcomes

## Define discharge outcomes

Use
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)
on numeric NIS Core fields before building a survey design. It adds
three columns and leaves the query in DuckDB. The example uses invented
discharges.

Negative HCUP missing-value sentinels and non-integer values become `NA`
in the derived outcomes.

``` r

outcomes <- nis_open(nis_example(years = 2024)) |>
  nis_outcomes()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpmJGVhp/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpmJGVhp/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.

design <- nis_design(
  outcomes,
  cohort = TRUE,
  keep = c(in_hospital_death, los_days, discharge_disposition, TOTCHG, CCR_NIS),
  dollars = 2024
)
#> Cohort: 96 discharges; weighted N 114.4; 12 hospitals across 1 years.
```

- **In-hospital mortality.** `in_hospital_death` is the 0/1 indicator
  from `DIED`. A discharge alive contributes zero. Missing or invalid
  `DIED` stays missing even when a disposition is recorded. The event is
  death during the sampled hospitalization. [HCUP DIED
  notes](https://hcup-us.ahrq.gov/db/vars/died/nisnote.jsp)
- **Length of stay.** `los_days` uses HCUP’s edited `LOS` in whole days,
  including zero for admission and discharge on the same date. Deaths
  and transfers can have recorded LOS for the sampled stay. [HCUP LOS
  notes](https://hcup-us.ahrq.gov/db/vars/los/nisnote.jsp)
- **Discharge disposition.** `discharge_disposition` labels
  `DISPUNIFORM`. Code 2 denotes transfer to a short-term hospital. Code
  5 covers several types of other facilities, including skilled nursing
  and intermediate care. Code 6 includes home health, home IV, and home
  hospice. Codes 21 (court/law enforcement) and 99 (alive with
  destination unknown) are valid categories. An invalid or missing code
  yields a missing label. [HCUP DISPUNIFORM
  notes](https://hcup-us.ahrq.gov/db/vars/dispuniform/nisnote.jsp)

These are Core fields on both sides of the 2015 ICD transition. Review
the source year’s coding before pooling releases. Historical `DISP` and
detailed billing disposition fields use different codes.

## Choose an estimator

For mortality, the survey-weighted mean of the indicator is the
proportion of discharges with known status that ended in death. For
disposition, use survey-weighted category proportions and state whether
the denominator includes in-hospital deaths and the known-alive,
unknown-destination group. For skewed LOS, survey quantiles give the
median and the 25th and 75th percentiles while retaining same-day stays.

``` r

survey::svymean(~in_hospital_death, design, na.rm = TRUE)
#>                       mean     SE
#> in_hospital_death 0.020105 0.0117
survey::svymean(~factor(discharge_disposition), design, na.rm = TRUE)
#>                                                                                       mean
#> factor(discharge_disposition)Alive, destination unknown                              0.125
#> factor(discharge_disposition)Died in hospital                                        0.125
#> factor(discharge_disposition)Discharged/transferred to court/law enforcement         0.125
#> factor(discharge_disposition)Home health care                                        0.125
#> factor(discharge_disposition)Left against medical advice                             0.125
#> factor(discharge_disposition)Routine discharge to home/self-care                     0.125
#> factor(discharge_disposition)Transfer to another short-term hospital                 0.125
#> factor(discharge_disposition)Transfer to SNF, intermediate care, or another facility 0.125
#>                                                                                      SE
#> factor(discharge_disposition)Alive, destination unknown                               0
#> factor(discharge_disposition)Died in hospital                                         0
#> factor(discharge_disposition)Discharged/transferred to court/law enforcement          0
#> factor(discharge_disposition)Home health care                                         0
#> factor(discharge_disposition)Left against medical advice                              0
#> factor(discharge_disposition)Routine discharge to home/self-care                      0
#> factor(discharge_disposition)Transfer to another short-term hospital                  0
#> factor(discharge_disposition)Transfer to SNF, intermediate care, or another facility  0
survey::svyquantile(~los_days, design, c(0.25, 0.5, 0.75), na.rm = TRUE)
#> $los_days
#>      quantile ci.2.5 ci.97.5       se
#> 0.25        3      3       4 0.221028
#> 0.5         6      6       7 0.221028
#> 0.75        9      9      10 0.221028
#> 
#> attr(,"hasci")
#> [1] TRUE
#> attr(,"class")
#> [1] "newsvyquantile"
```

A geometric mean of LOS requires positive values for the log. If the
question concerns positive stays, define that survey domain explicitly
and exponentiate its weighted mean log LOS and confidence limits. Report
the share of same-day stays and the rule used for zeros. Adding a
constant to all stays changes the scale of the quantity being estimated.
A NIS heart failure study reported geometric means after substituting a
small positive value for zeros, an analysis choice to document when
reproducing that study. [Heart failure utilization
study](https://pmc.ncbi.nlm.nih.gov/articles/PMC6676288/)

## Report costs and the analysis denominator

`nis_design(..., dollars = 2024)` uses the same adjustment as
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
to calculate `cost_adj` from charges and the hospital cost-to-charge
ratio. Report the price index and reference dollar year. Use a
survey-weighted arithmetic mean for cost per discharge or a
survey-weighted median and quartiles for the distribution of costs.

``` r

survey::svymean(~cost_adj, design, na.rm = TRUE)
#>            mean     SE
#> cost_adj 4368.3 54.991
nis_cost_provenance(design)$base_year
#> [1] 2024
```

For resource use across all discharges, include stays ending in death
when LOS or cost is observed. A survivor-only analysis answers a
different question. For example, a study of craniotomy costs excluded
in-hospital deaths and stays with withdrawal of care, while a pulmonary
disease study estimated LOS and costs specifically for stays ending in
death. State which population each summary describes. [Craniotomy cost
study](https://pmc.ncbi.nlm.nih.gov/articles/PMC4351828/) · [End-of-life
pulmonary hospitalization
study](https://pmc.ncbi.nlm.nih.gov/articles/PMC11251072/)

Check and report missingness by outcome and comparison group before
using `na.rm = TRUE`. Each summary then uses its own observed-outcome
denominator. Missing or invalid charges or CCRs can leave cost
unobserved even for stays with known LOS. A complete-cost summary
describes the discharges with calculable costs. If missingness differs
by year, group, or survival status, assess how that affects comparisons
and any inference to all discharges. One NIS study of prolonged stays
used weighted medians and quartiles for non-normal outcomes and complete
cases for its mortality regression. [Prolonged hospitalization
study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5362287/)

See [Charges, costs, and
provenance](https://msaadasif.github.io/easyNIS/articles/costs.md) and
[Disclosure
review](https://msaadasif.github.io/easyNIS/articles/disclosure.md)
before reporting results.
