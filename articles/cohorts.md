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
#> ℹ /tmp/RtmpG5BUVS/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpG5BUVS/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpG5BUVS/duckdb
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

## Use a CCSR reference file

easyNIS does not ship clinical code lists.
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md)
reads an analyst-supplied HCUP reference file; the example below writes
a tiny invented CSV file and removes it after use.

``` r

reference <- tempfile(fileext = ".csv")
writeLines(c(
  "'ICD-10-CM CODE','CCSR CATEGORY 1','DEFAULT CCSR CATEGORY IP'",
  "'I5022','CIR019','CIR019'",
  "'I509','CIR019','CIR019'"
), reference)
codes <- nis_ccsr_codes(reference, "CIR019", default_only = TRUE)
unlink(reference)
codes
#> [1] "I5022" "I509"
```

The returned values are codes from the invented mapping. Check supported
layouts and version assumptions in
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md).

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

[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md)
reports sequential unweighted and weighted counts for conditions
supplied in order.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpG5BUVS/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpG5BUVS/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_attrition(nis, adults = AGE >= 18, heart_failure = heart_failure)
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
#> # A tibble: 3 × 7
#>    step criterion      n_unweighted n_dropped_unweighted n_weighted
#>   <int> <chr>                 <int>                <int>      <dbl>
#> 1     0 All discharges           96                    0      114. 
#> 2     1 adults                   96                    0      114. 
#> 3     2 heart_failure            54                   42       62.4
#> # ℹ 2 more variables: n_dropped_weighted <dbl>, pct_retained <dbl>
```

Each row shows the remaining fixture discharges after applying that
step. For alternate diagnosis positions and changes over time, see [Code
transitions and
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
