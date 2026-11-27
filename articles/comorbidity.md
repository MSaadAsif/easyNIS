# Comorbidity indicators

[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
scores secondary diagnoses within each discharge in DuckDB. For a lazy
input, it checks the discharge keys and code availability and returns a
query. The flags and indices are calculated when that query runs.

## Choose a definition

| `method` | Coding definition and published weights |
|----|----|
| `elixhauser_ahrq_icd10` (default) | Union of AHRQ Refined ICD-10-CM FY2022–FY2026 codes and the latest weights in medicalcoder 0.10.0. |
| `elixhauser_ahrq2022` through `elixhauser_ahrq2026` | Pinned AHRQ Refined ICD-10-CM definitions and their in-hospital mortality and 30-day readmission weights, supplied by medicalcoder. |
| `elixhauser_ahrq2027` | AHRQ Refined ICD-10-CM v2027.1. Exemptions are selected by discharge fiscal year when available. |
| `charlson_quan2005` | Quan 2005 ICD-9-CM and ICD-10 coding with the original Charlson weights. |
| `charlson_quan2011` | Quan 2005 ICD-9-CM and ICD-10 coding with Quan 2011 weights. |
| `charlson_deyo1992` | Deyo 1992 ICD-9-CM coding with the original Charlson weights. Eligible ICD-9-CM procedure slots are used when supplied. |
| `elixhauser_quan2005` | Quan 2005 ICD-9-CM and ICD-10 Elixhauser coding with legacy AHRQ index weights, as supplied by medicalcoder. |
| `elixhauser_ahrq_web`, `elixhauser_elixhauser1998` | Legacy ICD-9-CM code mappings and AHRQ index weights, as supplied by medicalcoder. The scorer uses diagnosis codes without diagnosis-related group exclusions. |

The Charlson score is unadjusted for age. For the scientific
definitions, see [Charlson et
al. (1987)](https://doi.org/10.1016/0021-9681(87)90171-8), [Deyo et
al. (1992)](https://doi.org/10.1016/0895-4356(92)90133-8), [Elixhauser
et al. (1998)](https://doi.org/10.1097/00005650-199801000-00004), [Quan
et al. (2005)](https://doi.org/10.1097/01.mlr.0000182534.19832.83),
[Quan et al. (2011)](https://doi.org/10.1093/aje/kwq433), [Moore et
al. (2017)](https://doi.org/10.1097/MLR.0000000000000735), and the [AHRQ
Refined software and user
guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/comorbidity_icd10.jsp).

Methods other than FY2027 use mappings from
[medicalcoder](https://CRAN.R-project.org/package=medicalcoder). Install
it with `install.packages("medicalcoder")`. It remains an optional
dependency so workflows that do not use those definitions avoid the
extra download, about 3.3 MB for the 0.10.0 source archive. CRAN
publishes Windows and macOS binaries. CRAN’s Linux source package needs
no compilation and has no additional mandatory package dependencies.

## Score a lazy cohort

``` r

discharges <- nis_open(nis_example(years = 2019)) |>
  dplyr::filter(AGE >= 18)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYWRNlv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYWRNlv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
scored <- nis_comorbidity(discharges, method = "elixhauser_ahrq2027")
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

The fixture includes invented discharge keys in `KEY_NIS`. When pooling
years, keep `YEAR` because keys can repeat across years. Keep eligible
`DX*` and `I10_DX*` slots plus `YEAR`, `DQTR`, and `DXVER` where
available when scoring data across the October 2015 transition. The
selected method determines which coding systems are eligible.

## Score a survey design

Keep diagnosis and available POA columns in the design to add the
indicators after constructing it. Weights, strata and clusters are
preserved.

``` r

nis <- nis_open(nis_example(years = 2019)) |>
  nis_flag_dx(heart_failure = "I50")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYWRNlv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYWRNlv/duckdb
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
scored_design <- nis_comorbidity(design, method = "elixhauser_ahrq2027")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpYWRNlv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
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

## Interpret missing values

A record with a usable code and zero mapped conditions gets zero scores.
A discharge without a usable code for the selected definition gets
missing scores. Keep the original ICD-9-CM codes as strings so that
leading zeros survive.

For refined Elixhauser and Charlson, `Y` and `W` count as present on
admission, `N` and `U` mean absent, and other values including `1` are
unknown. Refined Elixhauser uses its code-level exemptions. The
medicalcoder-based releases use its fixed exemption mapping. FY2027 uses
`YEAR` plus one for October through December, the calendar year if the
quarter is missing, or the latest available exemption list if the year
is missing or beyond that release.

If a matching POA column is absent, easyNIS assumes the corresponding
diagnoses were present and warns which slots are affected. The
assumption can include conditions acquired during a hospital stay. AHRQ
leaves 18 refined measures unset when POA is unavailable, and intends
its indices to use all 38 measures. Report the assumption and method
when publishing results.

NIS studies may carry Stata-derived `ynel*` and `elixsum` columns. They
use earlier definitions, so their values may differ from these scores.

See [the function
reference](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
and [Data notes by
year](https://msaadasif.github.io/easyNIS/articles/year-notes.md).
