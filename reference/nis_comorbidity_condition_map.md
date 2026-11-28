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

[Derive outcomes, comorbidities, and
costs](https://msaadasif.github.io/easyNIS/articles/outcomes-and-costs.html).

Other outcomes and costs:
[`nis_comorbidity()`](https://msaadasif.github.io/easyNIS/reference/nis_comorbidity.md),
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md),
[`nis_cost_provenance()`](https://msaadasif.github.io/easyNIS/reference/nis_cost_provenance.md),
[`nis_outcomes()`](https://msaadasif.github.io/easyNIS/reference/nis_outcomes.md)

## Examples

``` r
map <- nis_comorbidity_condition_map("elixhauser_ahrq2027", prefix = "risk_")
subset(map, condition == "diabetes")
#>            output condition
#> 16   risk_diab_cx  diabetes
#> 17 risk_diab_uncx  diabetes
```
