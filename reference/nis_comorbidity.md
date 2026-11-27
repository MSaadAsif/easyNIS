# Add comorbidity indicators and scores (experimental)

DuckDB unpivots diagnosis slots, maps codes to conditions, and applies
present-on-admission and hierarchy rules within each discharge. Lazy
queries stay in DuckDB. The function runs a key and
diagnosis-availability check before returning the score query. Collected
data frames keep their row order.

## Usage

``` r
nis_comorbidity(.data, method = "elixhauser_ahrq_icd10", prefix = "cmrb_")
```

## Arguments

- .data:

  A data frame, a `tbl_svy` from
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md),
  or a lazy DuckDB query. Lazy input requires non-missing, unique
  `KEY_NIS`, or unique pairs of `YEAR` and `KEY_NIS` when `YEAR` is
  present. Keep `YEAR` when pooling years.

- method:

  Comorbidity definition. The default `"elixhauser_ahrq_icd10"` uses the
  medicalcoder ICD-10-CM union. `"elixhauser_ahrq2022"` through
  `"elixhauser_ahrq2027"` select a specific release. Use
  `"charlson_quan2005"` for Quan coding with original Charlson weights,
  `"charlson_quan2011"` for the same coding with Quan 2011 weights, and
  `"charlson_deyo1992"` for Deyo ICD-9-CM coding with original weights.
  `"elixhauser_quan2005"` uses Quan ICD-9-CM or ICD-10 coding and legacy
  AHRQ weights. `"elixhauser_ahrq_web"` and
  `"elixhauser_elixhauser1998"` replicate medicalcoder's legacy ICD-9
  code-based algorithms. All methods except FY2027 require the optional
  medicalcoder package.

- prefix:

  Prefix for the added columns. Choose a prefix that does not collide
  with an existing name.

## Value

`.data` with logical condition flags and `<prefix>any`, the integer
count `<prefix>n`, and either `<prefix>mortality_index` and
`<prefix>readmission_index` (Elixhauser) or `<prefix>cci` (Charlson).
Charlson scores are based on diagnoses and any mapped procedures without
an age adjustment.

## Coding and present on admission

- Use ICD-10-CM `I10_DX*` or ICD-9-CM `DX*` slots as supported by the
  method. The first slot identifies the principal diagnosis and is
  excluded from flags. When supplied, `YEAR`, `DQTR` and `DXVER`
  identify eligible diagnosis slots. Deyo also reads eligible ICD-9-CM
  `PR*` slots when available and mapped. Keep ICD-9 codes as strings to
  retain leading zeros.

- Codes use uppercase with periods and ASCII whitespace removed. Rows
  with usable codes that map to no conditions receive zeros. Rows
  without usable codes for the method receive missing scores and trigger
  a warning.

- Refined AHRQ and Charlson align `DXPOAn` to the diagnosis suffix `n`.
  `Y` and `W` mean present, `N` and `U` mean absent, and other values
  including `1` mean unknown. Refined AHRQ also uses code-specific
  exemptions. For methods sourced from medicalcoder, repeated diagnoses
  that map to the same category and exemption state follow its
  data.frame precedence (unknown, then present, then absent).

- If a matching POA field is absent, easyNIS warns and assumes those
  diagnoses were present. NIS releases generally lack POA indicators, so
  this assumption can count conditions acquired during a hospital stay.
  AHRQ's software leaves 18 of 38 measures unset when POA is
  unavailable.

- `elixhauser_ahrq2027` selects its exemption list using the discharge
  fiscal year (calendar `YEAR` plus one for `DQTR == 4`). When the
  quarter is missing it uses the calendar year. When the year is missing
  or after the release, it uses the latest fiscal year in the release.
  The other refined methods use medicalcoder's fixed exemptions.

## Use with [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)

Retain diagnosis slots and available POA fields using `keep`, then pass
the design to `nis_comorbidity()`. For a `tbl_svy`, only the design's
variables are enriched. The clusters, strata and weights are preserved.

## See also

[Comorbidity
indicators](https://msaadasif.github.io/easyNIS/reference/articles/comorbidity.md).

## Examples

``` r
discharges <- data.frame(I10_DX1 = "Z0000", I10_DX2 = "I509", DXPOA1 = "Y", DXPOA2 = "Y")
nis_comorbidity(discharges, method = "elixhauser_ahrq2027")$cmrb_mortality_index
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpaLGZww/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> [1] 14
```
