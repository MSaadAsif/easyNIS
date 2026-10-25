# Background: Why easyNIS

## Background

NIS estimates depend on getting the survey design, cohort, and reporting
rules right. HCUP publishes a methods checklist because these choices
are easy to miss in hand-built analyses. easyNIS puts common design and
disclosure steps on the normal path, while leaving the clinical question
and code sets with the analyst.

## Same cohort, more useful estimate

This example estimates the annualized weighted number of adult
discharges with heart failure and mean length of stay (LOS). The example
data are invented and intentionally small; the values demonstrate the
workflow, not national estimates.

The hand-rolled approach reads every annual file fully into memory,
pools the records, and filters before constructing the survey design.
The `# trap:` notes mark the lines where common design and reporting
errors enter.

``` r

path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
files <- list.files(path, pattern = "part-0[.]parquet$", recursive = TRUE,
                    full.names = TRUE)
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
all_years <- purrr::map_dfr(files, function(file) {
  DBI::dbGetQuery(con, paste("SELECT * FROM read_parquet(",
    as.character(DBI::dbQuoteString(con, file)), ")"))
}) # full annual reads
DBI::dbDisconnect(con, shutdown = TRUE)
all_years <- all_years |> dplyr::mutate(heart_failure =
  dplyr::if_any(dplyr::starts_with("I10_DX"), ~ startsWith(.x, "I50")),
  one = 1L)
cohort <- all_years |> dplyr::filter(AGE >= 18, heart_failure) # trap: subset before design
design <- survey::svydesign(
  ids = ~HOSP_NIS, # trap: HOSP_NIS is reused across years; YEAR is not in the PSU ID
  strata = ~NIS_STRATUM,
  weights = ~DISCWT, # trap: pooled weights are not annualized
  data = cohort, nest = TRUE
)
survey::svytotal(~one, design)
#>     total     SE
#> one 124.8 5.2307
survey::svymean(~LOS, design)
#>       mean     SE
#> LOS 5.6635 0.2988
# trap: no small-cell check before publishing a subgroup table
```

The total of `one` is a weighted discharge count; the mean LOS also
comes with a design-based standard error. With pooled years, the
hand-built estimates still need year-scoped identifiers and a stated
weight convention. Filtering first also removes sampled hospitals with
no cohort cases from the design.

``` r

path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path) |>
  nis_flag_dx(heart_failure = "I50") |>
  dplyr::mutate(one = 1L)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, cohort = AGE >= 18 & heart_failure,
                     keep = c(LOS, one), annualize = TRUE)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> Cohort: 108 discharges; weighted N 62.4; 18 hospitals across 2 years.
survey::svytotal(~one, design)
#>     total     SE
#> one  62.4 8.6741
survey::svymean(~LOS, design)
#>       mean    SE
#> LOS 5.6635 0.229
```

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
creates the survey design before applying the cohort domain, scopes
hospital and stratum IDs by year, and annualizes the weights while
retaining the design-based variance calculation.

The hand-rolled and easyNIS outputs use different design and pooling
conventions. Read the printed estimates and standard errors as a
demonstration of why those choices matter in this invented fixture; they
are not NIS population results. For the full reasoning and workflow, see
[Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md).

| Common hand-rolled problem | easyNIS | Function |
|----|----|----|
| Read and hold every annual file to work across years | Open annual Parquet data lazily with DuckDB | [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md) |
| Hand-code repeated diagnosis/procedure slot matching or position rules | Flag across slots, with principal/secondary position options for diagnoses and principal/any for procedures | `nis_flag_dx(position =)`; `nis_flag_pr(position =)` |
| Pool hospital IDs or leave pooled weights on a single-year scale | Build a domain design with year-scoped IDs and optional annualization | [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md) |
| Mix the ICD-9 and ICD-10 slot namespaces around the 2015 transition | Select the code system explicitly; 2015 checks use year and quarter/version fields when available | `system =` on [`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md) / [`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md) |
| Match procedures but lose the slot-specific procedure day | Compare procedure prefixes with their corresponding `PRDAY` fields | [`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md) |
| Recount every inclusion/exclusion step by hand | Produce sequential unweighted and weighted cohort attrition | [`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md) |
| Report only one diagnosis-position definition | Compare principal, secondary-only, and any-position diagnosis summaries | [`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md) |
| Miss shifts in code frequency between years | Audit code-group prevalence across periods | [`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md) |
| Treat charges as costs or apply an undocumented conversion | Convert charges using CCR and CPI-U and retain provenance | [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md) |
| Recreate comorbidity indicators from diagnosis slots | Compute the supported ICD-10 Elixhauser indicators | [`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md) |
| Publish small cells or cells from too few hospitals | Count supporting hospitals and suppress small or single-hospital cells | [`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md); [`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md) |
| Rebuild project scaffolding for each study | [`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md) creates a Quarto project with a starter analysis file; add data and make study-specific code, cohort, and design choices | [`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md) |

## Built-in safety checks

- [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  warns when annualization includes years with incomplete quarter
  coverage. It identifies 2015 cohorts limited to ICD-9 Q1–Q3 or ICD-10
  Q4, and reports when `DQTR` is unavailable for the split check.
- `nis_suppress(hospital_col =)` masks cells represented at fewer than
  two hospitals, as well as cells at or below the discharge threshold.
- [`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md)
  records charge and CCR inputs, CPI-U multipliers, base year, and
  invalid CCR rows; invalid CCR costs are `NA`.
- [`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)
  counts known, missing, negative/sentinel, and absent procedure-day
  fields by year and slot.

## One workflow

The same design can feed descriptive summaries and models. The
`tbl_svysummary()` suppression route checks discharge counts only. To
apply both discharge and two-hospital rules before sharing cell counts,
use
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md)
with data-frame suppression.

``` r

path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path) |> nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(nis, cohort = AGE >= 18,
  keep = c(AGE, LOS, heart_failure), annualize = TRUE)
#> Cohort: 192 discharges; weighted N 114.4; 24 hospitals across 2 years.
table_one <- gtsummary::tbl_svysummary(
  design, by = heart_failure, include = c(AGE, LOS)
) |>
  nis_suppress(threshold = 10)
#> `nis_suppress()` on a `tbl_svysummary` checks discharge counts only; it does
#> not apply the two-hospital rule.
shareable_counts <- nis_cell_counts(
  dplyr::collect(nis), by = "heart_failure"
) |>
  nis_suppress(count_col = "n", hospital_col = "hospitals")
fit <- survey::svyglm(LOS ~ heart_failure + AGE, design = design)
table_one
shareable_counts
summary(fit)
```

## Three focused examples

See how a cohort definition changes the discharge count at each step:

``` r

nis <- nis_open(nis_example(years = 2019:2020))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis |> nis_flag_dx(heart_failure = "I50")
nis_attrition(nis, adults = AGE >= 18, heart_failure = heart_failure, by_year = TRUE)
#> # A tibble: 6 × 8
#>    YEAR  step criterion      n_unweighted n_dropped_unweighted n_weighted
#>   <int> <int> <chr>                 <int>                <int>      <dbl>
#> 1  2020     0 All discharges           96                    0      114. 
#> 2  2020     1 adults                   96                    0      114. 
#> 3  2020     2 heart_failure            54                   42       62.4
#> 4  2019     0 All discharges           96                    0      114. 
#> 5  2019     1 adults                   96                    0      114. 
#> 6  2019     2 heart_failure            54                   42       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
```

Check how a heart-failure definition changes when restricted to the
principal diagnosis:

``` r

nis <- nis_open(nis_example(years = 2019))
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp4yJCw6/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_dx_sensitivity(nis, "I50")
#> # A tibble: 3 × 9
#>   presentation n_unweighted n_weighted pct_of_any_unweighted pct_of_any_weighted
#>   <chr>               <dbl>      <dbl>                 <dbl>               <dbl>
#> 1 principal              54       62.4                   100                 100
#> 2 secondary_o…            0        0                       0                   0
#> 3 any                    54       62.4                   100                 100
#> # ℹ 4 more variables: DIED_rate_unweighted <dbl>, DIED_rate_weighted <dbl>,
#> #   ELECTIVE_rate_unweighted <dbl>, ELECTIVE_rate_weighted <dbl>
```

Here both procedures occur on each discharge, in different slots and on
different days. The timing flag is true only when the outcome procedure
is after the index procedure:

``` r

procedures <- tibble::tibble(I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ"),
  I10_PR2 = c("0JH604Z", "0JH604Z", "0JH604Z"), PRDAY1 = c(0L, 2L, 0L), PRDAY2 = c(1L, 1L, 0L))
nis_flag_pr_timing(procedures, "02UG0", "0JH60", relation = "after")
#> # A tibble: 3 × 5
#>   I10_PR1 I10_PR2 PRDAY1 PRDAY2 outcome_post_index
#>   <chr>   <chr>    <int>  <int> <lgl>             
#> 1 02UG0JZ 0JH604Z      0      1 TRUE              
#> 2 02UG0JZ 0JH604Z      2      1 FALSE             
#> 3 02UG0JZ 0JH604Z      0      0 FALSE
```

## Common pitfalls

> **Common pitfalls**
>
> - A workflow helper does not replace the official HCUP documentation,
>   clinical code-set decisions, or study-specific design review.
> - The placeholder-row variance strategy, cost method, ICD-9 support,
>   and AHRQ Elixhauser computation are experimental.
> - Suppression reduces disclosure risk but does not rule out every
>   deduction; review derived totals and follow the applicable DUA
>   process.

See [Get
started](https://msaadasif.github.io/easyNIS/getting-started.md),
[Survey design and
weighting](https://msaadasif.github.io/easyNIS/articles/survey-design.md),
and [Disclosure and
suppression](https://msaadasif.github.io/easyNIS/articles/disclosure.md).
