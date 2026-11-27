# Comorbidity indicators

[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
uses the optional `medicalcoder` package to apply its AHRQ Elixhauser
ICD-10-CM mapping. easyNIS does not distribute clinical code lists. This
computation is experimental and its assumptions need scientific review.

## Score a DuckDB cohort

Keep `KEY_NIS` and, for pooled years, `YEAR` with the diagnosis columns.
The function scores batches of up to 25,000 discharges, reading only the
keys, diagnoses and available POA fields into the scoring workflow. The
result remains a DuckDB query with the original columns and the added
indicators. Select the columns you need before collecting.

The example assigns stable keys to the invented fixture. NIS files
already include `KEY_NIS`.

``` r

discharges <- nis_open(nis_example(years = 2019)) |>
  dplyr::filter(AGE >= 18) |>
  dplyr::mutate(KEY_NIS = dplyr::row_number()) |>
  dplyr::compute()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeAqzSR/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeAqzSR/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
scored <- nis_comorbidity(discharges)
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
scored |>
  dplyr::select(AGE, cmrb_n, cmrb_any, cmrb_mortality_index) |>
  head() |>
  dplyr::collect()
#> # A tibble: 6 × 4
#>     AGE cmrb_n cmrb_any cmrb_mortality_index
#>   <dbl>  <int> <lgl>                   <int>
#> 1    28      1 TRUE                       14
#> 2    35      1 TRUE                        0
#> 3    42      1 TRUE                        0
#> 4    49      0 FALSE                       0
#> 5    56      1 TRUE                       14
#> 6    63      1 TRUE                        0
```

The added columns report the number of flagged conditions and whether
any were flagged. Values are computed from invented codes. Rows without
usable ICD-10 codes have missing results rather than “no comorbidity.”

Scores are computed when you call
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
and kept in a temporary table for the input connection. DuckDB reads the
original query again when you use its output, so score a stable cohort
with unique, non-missing keys. Collected data frames are also supported
and keep their original row order.

## Add scores after design construction

If an analysis uses
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
keep diagnosis columns in the design and pass the design to
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md).
This preserves the design object.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeAqzSR/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeAqzSR/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
design <- nis_design(
  nis,
  cohort = heart_failure,
  keep = c(AGE, dplyr::starts_with("I10_DX"), dplyr::starts_with("DXPOA"))
)
#> Cohort: 54 discharges; weighted N 62.4; 9 hospitals across 1 years.
scored_design <- nis_comorbidity(design)
#> Warning: No matching POA column for 40 diagnosis slots: I10_DX1, I10_DX10, I10_DX11,
#> I10_DX12, I10_DX13, I10_DX14, I10_DX15, I10_DX16, I10_DX17, I10_DX18, I10_DX19,
#> I10_DX2, I10_DX20, I10_DX21, I10_DX22, I10_DX23, I10_DX24, I10_DX25, I10_DX26,
#> I10_DX27, I10_DX28, I10_DX29, I10_DX3, I10_DX30, I10_DX31, I10_DX32, I10_DX33,
#> I10_DX34, I10_DX35, I10_DX36, I10_DX37, I10_DX38, I10_DX39, I10_DX4, I10_DX40,
#> I10_DX5, I10_DX6, I10_DX7, I10_DX8, I10_DX9. Assuming present.
#> ℹ POA-dependent comorbidities may include conditions acquired in hospital.
head(scored_design$variables[c("AGE", "cmrb_n", "cmrb_any")])
#> # A tibble: 6 × 3
#>     AGE cmrb_n cmrb_any
#>   <dbl>  <int> <lgl>   
#> 1    28      1 TRUE    
#> 2    35      1 TRUE    
#> 3    49      0 FALSE   
#> 4    56      1 TRUE    
#> 5    70      1 TRUE    
#> 6    77      1 TRUE
```

The survey design fields remain the same while the analysis variables
gain comorbidity indicators.

## Present on admission

AHRQ assigns 18 of its 38 refined Elixhauser measures using POA for
nonexempt secondary diagnoses. For those diagnoses, `Y` and `W` qualify.
NIS files lack POA indicators. AHRQ leaves those 18 measures missing
when POA inputs are unavailable and requires all 38 to calculate its
indices. Beginning in 2019, the NIS Diagnosis and Procedure Groups file
includes the available HCUP-derived measures. [AHRQ User
Guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/CMR-User-Guide-v2024-1.pdf),
[HCUP POA
availability](https://hcup-us.ahrq.gov/db/vars/sedddistnote.jsp?var=cmr_aaa),
[2019 NIS
introduction](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2019.jsp).

[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
retains its experimental assumption that a diagnosis was present on
admission when its entire `DXPOAn` field is absent. The warning
identifies the affected slots. This assumption can count conditions that
arose during the stay and alter the mortality and readmission scores.
When a matching field is present, `Y` and `W` count as POA, `N` and `U`
do not, and other values are unknown. In pooled data, a missing value in
an existing POA column remains unknown. `medicalcoder` supplies the
exempt-code mapping, which is shared across AHRQ releases in that
package and is applied without looking up the fiscal year for each
discharge.

Pre-October 2015 ICD-9 records receive missing results. Older
Stata-derived `ynel*` and `elixsum` fields use different definitions and
versions.

## Charlson in NIS studies

Charlson serves different purposes across studies. The national
inpatient norms study used Quan’s ICD-10 algorithms to describe
comorbidity burden by demographic groups. The NIS hepatitis C pregnancy
study used the Charlson–Deyo score as an adjustment covariate, grouping
it into 0, 1–2, and above 2. [National norms
study](https://doi.org/10.1093/gerona/glac087), [hepatitis C pregnancy
study](https://pmc.ncbi.nlm.nih.gov/articles/PMC10362466/).

easyNIS defers a Charlson option until it can specify and verify the
mapping, weights, diagnosis inclusion, and POA assumptions for a named
variant. `medicalcoder` supplies Quan 2005 and 2011 variants, with
distinct weights and explicit POA and principal-diagnosis inputs. The
`comorbidity` package offers a Quan ICD-10 map with separately
selectable original or revised weights and a severity hierarchy. For a
replication, choose these inputs using the study’s methods.
[`medicalcoder` Charlson
vignette](https://cran.r-project.org/web/packages/medicalcoder/vignettes/charlson.html),
[`comorbidity`
manual](https://cran.r-project.org/web/packages/comorbidity/comorbidity.pdf).

See
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
and [Data notes by
year](https://msaadasif.github.io/easyNIS/articles/year-notes.md).
