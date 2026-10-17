# Getting started with easyNIS

easyNIS takes you from annual National Inpatient Sample (NIS) Parquet
files to a survey-weighted table, with primary small cells suppressed.
This guide walks through the steps on
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
data: invented discharges that have the NIS column layout but no real
records. Replace the example path with the directory that holds your own
`NIS_<year>.parquet` files to run a real study.

## Open the data

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
opens the annual files lazily, so nothing is read into memory until you
ask for it. Mixed-case NIS column names are normalized across years;
wholly lower-case names are left unchanged.

``` r

path <- nis_example(years = 2019:2020)
nis <- nis_open(path)

nis |>
  dplyr::count(YEAR) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <int>
#> 1  2020    96
#> 2  2019    96
```

## Flag diagnoses and procedures

[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
and
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
add one logical column per named set of ICD-10 code prefixes. Each
diagnosis or procedure slot is checked on its own, and the work stays
lazy. Prefixes ignore case, periods, and spaces; stored codes must use
the NIS upper-case, period-free layout.

``` r

nis <- nis |>
  nis_flag_dx(
    heart_failure = "I50",
    palliative_care = "Z515"
  ) |>
  nis_flag_pr(ablation = "02L")

nis |>
  dplyr::count(heart_failure, palliative_care) |>
  dplyr::collect()
#> # A tibble: 4 × 3
#>   heart_failure palliative_care     n
#>   <lgl>         <lgl>           <int>
#> 1 TRUE          FALSE              88
#> 2 FALSE         FALSE              66
#> 3 TRUE          TRUE               20
#> 4 FALSE         TRUE               18
```

Use `position = "principal"` to look at the principal diagnosis only. To
build the prefix lists from an HCUP CCSR reference file that you
download yourself, see
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md).

## Build the survey design

[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
takes a cohort expression and the columns to keep, collects the cohort,
and returns a nested survey design. It adds a placeholder row for each
hospital-year with no cohort discharges, so variance estimates account
for the whole sample. It also labels coded fields, and, when `TOTCHG`
and `CCR_NIS` are kept, adds inflation-adjusted `cost_adj` and
`charges_adj`.

``` r

design <- nis_design(
  nis,
  cohort = heart_failure & AGE >= 18,
  keep = c(AGE, FEMALE, DIED, LOS, TOTCHG, CCR_NIS, palliative_care),
  dollars = 2024
)
#> Cohort: 108 discharges; weighted N 124.8; 18 hospitals across 2 years.
```

Discharges with a missing or invalid design field are excluded with a
warning that gives their number. The design-based tools in the survey
and srvyr packages work on the result as they would on any other design.

``` r

srvyr::summarise(
  design,
  discharges = srvyr::survey_total(),
  mean_los = srvyr::survey_mean(LOS)
)
#> # A tibble: 1 × 4
#>   discharges discharges_se mean_los mean_los_se
#>        <dbl>         <dbl>    <dbl>       <dbl>
#> 1       125.          17.3     5.66       0.229
```

## Table 1 and a model

[`gtsummary::tbl_svysummary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_svysummary.html)
builds a weighted table from the design, and
[`survey::svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) fits a
model that uses the survey structure.

The table chunks need the optional gtsummary, cardx, survey, and gt
packages. Install them before running this guide if they are not already
available.

``` r

table_one <- gtsummary::tbl_svysummary(
  design,
  by = palliative_care,
  include = c(AGE, FEMALE, LOS, cost_adj)
) |>
  gtsummary::add_overall()
```

``` r

fit <- survey::svyglm(
  LOS ~ palliative_care + AGE + FEMALE + factor(YEAR),
  design = design
)

summary(fit)
#> 
#> Call:
#> svyglm(formula = LOS ~ palliative_care + AGE + FEMALE + factor(YEAR), 
#>     design = design)
#> 
#> Survey design:
#> Called via srvyr
#> 
#> Coefficients:
#>                      Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)         6.132e+00  6.441e-01   9.520 1.22e-05 ***
#> palliative_careYes  1.679e+00  9.073e-01   1.850   0.1014    
#> AGE                -5.156e-03  1.310e-02  -0.394   0.7041    
#> FEMALEFemale       -9.736e-01  3.230e-01  -3.014   0.0167 *  
#> factor(YEAR)2020   -6.013e-16  4.318e-01   0.000   1.0000    
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> (Dispersion parameter for gaussian family taken to be 11.32638)
#> 
#> Number of Fisher Scoring iterations: 2
```

## Suppress small cells

HCUP data use agreements require suppressing cells that describe 10 or
fewer discharges.
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
masks displayed statistics whose unweighted count is at or below the
threshold, along with the overall cell in the same row, and adds a
footnote that says so. Review tables for other derivable cells, such as
column totals, before you share them.

``` r

nis_suppress(table_one, threshold = 10)
```

[TABLE]

## Start a study folder

[`nis_new_study()`](https://msaadasif.github.io/easyNIS/reference/nis_new_study.md)
copies a Quarto template to a new directory. The template reproduces the
steps above as a report with cohort flow, Table 1, outcomes, yearly
trends, and regression tables. Its `analysis.qmd` runs on invented data
until you set its `data_path` parameter.

``` r

study <- tempfile("my-nis-study-")
nis_new_study(study)
#> [1] "/tmp/RtmpYvO0G4/my-nis-study-1c12152e8c24"
list.files(study, all.files = TRUE, no.. = TRUE)
#> [1] "_quarto.yml"  ".gitignore"   "analysis.qmd"
```

Edit the definitions block in `analysis.qmd` for your cohort, then
render it with Quarto.

## Where next

The “Porting an existing NIS study to easyNIS” vignette maps common
regular-expression and recoding steps to easyNIS.
[`nis_reweight()`](https://msaadasif.github.io/easyNIS/reference/nis_reweight.md)
applies propensity weights to a design, and
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
adds AHRQ Elixhauser columns; both are experimental.
