# Map comorbidity output flags to distinct conditions

Inspect the condition IDs used by
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)
when `count_distinct = TRUE`. A flag that represents multiple conditions
has one row per component. Severity variants share an ID. For example,
both diabetes flags map to `diabetes`, and refined Elixhauser's solid
tumor and metastatic cancer flags map to `solid_cancer`. Leukemia and
lymphoma retain separate IDs. Charlson's malignancy and metastatic solid
tumor flags both map to `malignancy`, because its malignancy flag also
covers leukemia and lymphoma.

## Usage

``` r
nis_comorbidity_condition_map(
  method = "elixhauser_ahrq_icd10",
  prefix = "cmrb_"
)
```

## Arguments

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
  code-based algorithms. All methods except `"elixhauser_ahrq2027"`
  require the medicalcoder package.

- prefix:

  Prefix for the added columns. Choose a prefix that does not collide
  with an existing name.

## Value

A data frame with character columns `output` (the prefixed logical
column name) and `condition` (the unprefixed ID to count or exclude).
The map omits summary counts, indices, and the `any` flag.

## Details

The map describes the emitted flags, including medicalcoder combination
and compatibility flags. For example, `hfhtn_cxrenlfl_sev` maps to heart
failure (`hf`), `hypertension`, and `renal_failure`. The count takes the
union of the conditions represented by true flags. It applies no further
hierarchy or present-on-admission adjudication.

## References

AHRQ HCUP. [Elixhauser Comorbidity Software Refined for
ICD-10-CM](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/comorbidity_icd10.jsp).

Dewitt PE. [medicalcoder](https://github.com/dewittpe/medicalcoder),
version 0.10.0. The combination flag names and decomposition follow the
package's refined Elixhauser mappings.

Quan H et al. [Coding algorithms for defining comorbidities in ICD-9-CM
and ICD-10 administrative
data](https://pubmed.ncbi.nlm.nih.gov/16224307/). Med Care.
2005;43(11):1130–1139.

## See also

Other comorbidity:
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md)

## Examples

``` r
nis_comorbidity_condition_map("elixhauser_ahrq2027", prefix = "risk_")
#>               output     condition
#> 1          risk_aids          aids
#> 2       risk_alcohol       alcohol
#> 3       risk_anemdef       anemdef
#> 4    risk_autoimmune    autoimmune
#> 5       risk_bldloss       bldloss
#> 6   risk_cancer_leuk   cancer_leuk
#> 7  risk_cancer_lymph  cancer_lymph
#> 8   risk_cancer_mets  solid_cancer
#> 9  risk_cancer_nsitu  solid_cancer
#> 10 risk_cancer_solid  solid_cancer
#> 11         risk_cbvd          cbvd
#> 12           risk_hf            hf
#> 13         risk_coag          coag
#> 14     risk_dementia      dementia
#> 15      risk_depress       depress
#> 16      risk_diab_cx      diabetes
#> 17    risk_diab_uncx      diabetes
#> 18         risk_drug          drug
#> 19       risk_htn_cx  hypertension
#> 20     risk_htn_uncx  hypertension
#> 21    risk_liver_mld liver_disease
#> 22    risk_liver_sev liver_disease
#> 23 risk_lung_chronic  lung_chronic
#> 24   risk_neuro_movt    neuro_movt
#> 25    risk_neuro_oth     neuro_oth
#> 26   risk_neuro_seiz    neuro_seiz
#> 27        risk_obese         obese
#> 28    risk_paralysis     paralysis
#> 29     risk_perivasc      perivasc
#> 30    risk_psychoses     psychoses
#> 31     risk_pulmcirc      pulmcirc
#> 32   risk_renlfl_mod renal_failure
#> 33   risk_renlfl_sev renal_failure
#> 34 risk_thyroid_hypo  thyroid_hypo
#> 35  risk_thyroid_oth   thyroid_oth
#> 36 risk_ulcer_peptic  ulcer_peptic
#> 37        risk_valve         valve
#> 38     risk_wghtloss      wghtloss
```
