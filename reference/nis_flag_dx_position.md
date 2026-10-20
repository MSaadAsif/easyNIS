# Add diagnosis position flags

Adds flags for a diagnosis prefix in the principal position, secondary
positions only, and any position. Prefix matching and code-system
eligibility follow
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md).

## Usage

``` r
nis_flag_dx_position(.data, code, name = "dx", system = c("icd10", "icd9"))
```

## Arguments

- .data:

  A data frame or lazy Arrow query.

- code:

  Non-missing character vector of diagnosis prefixes.

- name:

  Base name for the added columns. The function adds `<name>_principal`,
  `<name>_secondary_only`, and `<name>_any`.

- system:

  Code system of the diagnosis slots: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

## Value

`.data` with three logical diagnosis-position columns.

## See also

[Defining
cohorts](https://msaadasif.github.io/easyNIS/reference/articles/cohorts.md).

Other cohort-definition:
[`nis_attrition()`](https://msaadasif.github.io/easyNIS/reference/nis_attrition.md),
[`nis_audit_code_transition()`](https://msaadasif.github.io/easyNIS/reference/nis_audit_code_transition.md),
[`nis_ccsr_codes()`](https://msaadasif.github.io/easyNIS/reference/nis_ccsr_codes.md),
[`nis_dx_sensitivity()`](https://msaadasif.github.io/easyNIS/reference/nis_dx_sensitivity.md),
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md),
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md),
[`nis_flag_pr_timing()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr_timing.md),
[`nis_prday_completeness()`](https://msaadasif.github.io/easyNIS/reference/nis_prday_completeness.md)

## Examples

``` r
nis <- nis_open(nis_example(years = 2019))
nis_flag_dx_position(nis, "I50", name = "heart_failure")
#> FileSystemDataset (query)
#> AGE: double
#> AGE_NEONATE: int32
#> AMONTH: int32
#> APRDRG_RISK_MORTALITY: int32
#> APRDRG_SEVERITY: int32
#> AWEEKEND: int32
#> CCR_NIS: double
#> DIED: int32
#> DISCWT: double
#> DISPUNIFORM: double
#> DQTR: int32
#> DRG_NOPOA: int32
#> ELECTIVE: int32
#> FEMALE: int32
#> HCUP_ED: int32
#> HOSP_BEDSIZE: int32
#> HOSP_DIVISION: int32
#> HOSP_LOCTEACH: int32
#> HOSP_NIS: int32
#> HOSP_REGION: int32
#> H_CONTRL: int32
#> I10_BIRTH: int32
#> I10_DELIVERY: int32
#> I10_DX1: string
#> I10_DX10: string
#> I10_DX11: string
#> I10_DX12: string
#> I10_DX13: string
#> I10_DX14: string
#> I10_DX15: string
#> I10_DX16: string
#> I10_DX17: string
#> I10_DX18: string
#> I10_DX19: string
#> I10_DX2: string
#> I10_DX20: string
#> I10_DX21: string
#> I10_DX22: string
#> I10_DX23: string
#> I10_DX24: string
#> I10_DX25: string
#> I10_DX26: string
#> I10_DX27: string
#> I10_DX28: string
#> I10_DX29: string
#> I10_DX3: string
#> I10_DX30: string
#> I10_DX31: string
#> I10_DX32: string
#> I10_DX33: string
#> I10_DX34: string
#> I10_DX35: string
#> I10_DX36: string
#> I10_DX37: string
#> I10_DX38: string
#> I10_DX39: string
#> I10_DX4: string
#> I10_DX40: string
#> I10_DX5: string
#> I10_DX6: string
#> I10_DX7: string
#> I10_DX8: string
#> I10_DX9: string
#> I10_INJURY: int32
#> I10_MULTINJURY: int32
#> I10_NDX: int32
#> I10_NPR: int32
#> I10_PR1: string
#> I10_PR10: string
#> I10_PR11: string
#> I10_PR12: string
#> I10_PR13: string
#> I10_PR14: string
#> I10_PR15: string
#> I10_PR16: string
#> I10_PR17: string
#> I10_PR18: string
#> I10_PR19: string
#> I10_PR2: string
#> I10_PR20: string
#> I10_PR21: string
#> I10_PR22: string
#> I10_PR23: string
#> I10_PR24: string
#> I10_PR25: string
#> I10_PR3: string
#> I10_PR4: string
#> I10_PR5: string
#> I10_PR6: string
#> I10_PR7: string
#> I10_PR8: string
#> I10_PR9: string
#> I10_SERVICELINE: int32
#> LOS: double
#> MDC_NOPOA: int32
#> NIS_STRATUM: int32
#> PAY1: int32
#> PCLASS_ORPROC: int32
#> PL_NCHS: int32
#> RACE: int32
#> TOTCHG: double
#> TRAN_IN: int32
#> TRAN_OUT: int32
#> YEAR: int32
#> ZIPINC_QRTL: int32
#> elixsum: double
#> ynel1: int32
#> ynel2: int32
#> heart_failure_principal: bool ((((is_null(YEAR, {nan_is_null=true}) or (YEAR >= 2015)) and (((is_null(YEAR, {nan_is_null=true}) or (YEAR != 2015)) or is_null(DQTR, {nan_is_null=true})) or is_in(DQTR, {value_set=int32:[
#>   4
#> ], null_matching_behavior=SKIP}))) and coalesce(starts_with(I10_DX1, {pattern="I50", ignore_case=false}), false)))
#> heart_failure_any: bool ((((is_null(YEAR, {nan_is_null=true}) or (YEAR >= 2015)) and (((is_null(YEAR, {nan_is_null=true}) or (YEAR != 2015)) or is_null(DQTR, {nan_is_null=true})) or is_in(DQTR, {value_set=int32:[
#>   4
#> ], null_matching_behavior=SKIP}))) and coalesce((((((((((((((((((((((((((((((((((((((((starts_with(I10_DX1, {pattern="I50", ignore_case=false}) or starts_with(I10_DX10, {pattern="I50", ignore_case=false})) or starts_with(I10_DX11, {pattern="I50", ignore_case=false})) or starts_with(I10_DX12, {pattern="I50", ignore_case=false})) or starts_with(I10_DX13, {pattern="I50", ignore_case=false})) or starts_with(I10_DX14, {pattern="I50", ignore_case=false})) or starts_with(I10_DX15, {pattern="I50", ignore_case=false})) or starts_with(I10_DX16, {pattern="I50", ignore_case=false})) or starts_with(I10_DX17, {pattern="I50", ignore_case=false})) or starts_with(I10_DX18, {pattern="I50", ignore_case=false})) or starts_with(I10_DX19, {pattern="I50", ignore_case=false})) or starts_with(I10_DX2, {pattern="I50", ignore_case=false})) or starts_with(I10_DX20, {pattern="I50", ignore_case=false})) or starts_with(I10_DX21, {pattern="I50", ignore_case=false})) or starts_with(I10_DX22, {pattern="I50", ignore_case=false})) or starts_with(I10_DX23, {pattern="I50", ignore_case=false})) or starts_with(I10_DX24, {pattern="I50", ignore_case=false})) or starts_with(I10_DX25, {pattern="I50", ignore_case=false})) or starts_with(I10_DX26, {pattern="I50", ignore_case=false})) or starts_with(I10_DX27, {pattern="I50", ignore_case=false})) or starts_with(I10_DX28, {pattern="I50", ignore_case=false})) or starts_with(I10_DX29, {pattern="I50", ignore_case=false})) or starts_with(I10_DX3, {pattern="I50", ignore_case=false})) or starts_with(I10_DX30, {pattern="I50", ignore_case=false})) or starts_with(I10_DX31, {pattern="I50", ignore_case=false})) or starts_with(I10_DX32, {pattern="I50", ignore_case=false})) or starts_with(I10_DX33, {pattern="I50", ignore_case=false})) or starts_with(I10_DX34, {pattern="I50", ignore_case=false})) or starts_with(I10_DX35, {pattern="I50", ignore_case=false})) or starts_with(I10_DX36, {pattern="I50", ignore_case=false})) or starts_with(I10_DX37, {pattern="I50", ignore_case=false})) or starts_with(I10_DX38, {pattern="I50", ignore_case=false})) or starts_with(I10_DX39, {pattern="I50", ignore_case=false})) or starts_with(I10_DX4, {pattern="I50", ignore_case=false})) or starts_with(I10_DX40, {pattern="I50", ignore_case=false})) or starts_with(I10_DX5, {pattern="I50", ignore_case=false})) or starts_with(I10_DX6, {pattern="I50", ignore_case=false})) or starts_with(I10_DX7, {pattern="I50", ignore_case=false})) or starts_with(I10_DX8, {pattern="I50", ignore_case=false})) or starts_with(I10_DX9, {pattern="I50", ignore_case=false})), false)))
#> heart_failure_secondary_only: bool (((((is_null(YEAR, {nan_is_null=true}) or (YEAR >= 2015)) and (((is_null(YEAR, {nan_is_null=true}) or (YEAR != 2015)) or is_null(DQTR, {nan_is_null=true})) or is_in(DQTR, {value_set=int32:[
#>   4
#> ], null_matching_behavior=SKIP}))) and coalesce((((((((((((((((((((((((((((((((((((((((starts_with(I10_DX1, {pattern="I50", ignore_case=false}) or starts_with(I10_DX10, {pattern="I50", ignore_case=false})) or starts_with(I10_DX11, {pattern="I50", ignore_case=false})) or starts_with(I10_DX12, {pattern="I50", ignore_case=false})) or starts_with(I10_DX13, {pattern="I50", ignore_case=false})) or starts_with(I10_DX14, {pattern="I50", ignore_case=false})) or starts_with(I10_DX15, {pattern="I50", ignore_case=false})) or starts_with(I10_DX16, {pattern="I50", ignore_case=false})) or starts_with(I10_DX17, {pattern="I50", ignore_case=false})) or starts_with(I10_DX18, {pattern="I50", ignore_case=false})) or starts_with(I10_DX19, {pattern="I50", ignore_case=false})) or starts_with(I10_DX2, {pattern="I50", ignore_case=false})) or starts_with(I10_DX20, {pattern="I50", ignore_case=false})) or starts_with(I10_DX21, {pattern="I50", ignore_case=false})) or starts_with(I10_DX22, {pattern="I50", ignore_case=false})) or starts_with(I10_DX23, {pattern="I50", ignore_case=false})) or starts_with(I10_DX24, {pattern="I50", ignore_case=false})) or starts_with(I10_DX25, {pattern="I50", ignore_case=false})) or starts_with(I10_DX26, {pattern="I50", ignore_case=false})) or starts_with(I10_DX27, {pattern="I50", ignore_case=false})) or starts_with(I10_DX28, {pattern="I50", ignore_case=false})) or starts_with(I10_DX29, {pattern="I50", ignore_case=false})) or starts_with(I10_DX3, {pattern="I50", ignore_case=false})) or starts_with(I10_DX30, {pattern="I50", ignore_case=false})) or starts_with(I10_DX31, {pattern="I50", ignore_case=false})) or starts_with(I10_DX32, {pattern="I50", ignore_case=false})) or starts_with(I10_DX33, {pattern="I50", ignore_case=false})) or starts_with(I10_DX34, {pattern="I50", ignore_case=false})) or starts_with(I10_DX35, {pattern="I50", ignore_case=false})) or starts_with(I10_DX36, {pattern="I50", ignore_case=false})) or starts_with(I10_DX37, {pattern="I50", ignore_case=false})) or starts_with(I10_DX38, {pattern="I50", ignore_case=false})) or starts_with(I10_DX39, {pattern="I50", ignore_case=false})) or starts_with(I10_DX4, {pattern="I50", ignore_case=false})) or starts_with(I10_DX40, {pattern="I50", ignore_case=false})) or starts_with(I10_DX5, {pattern="I50", ignore_case=false})) or starts_with(I10_DX6, {pattern="I50", ignore_case=false})) or starts_with(I10_DX7, {pattern="I50", ignore_case=false})) or starts_with(I10_DX8, {pattern="I50", ignore_case=false})) or starts_with(I10_DX9, {pattern="I50", ignore_case=false})), false)) and invert((((is_null(YEAR, {nan_is_null=true}) or (YEAR >= 2015)) and (((is_null(YEAR, {nan_is_null=true}) or (YEAR != 2015)) or is_null(DQTR, {nan_is_null=true})) or is_in(DQTR, {value_set=int32:[
#>   4
#> ], null_matching_behavior=SKIP}))) and coalesce(starts_with(I10_DX1, {pattern="I50", ignore_case=false}), false)))))
#> 
#> See $.data for the source Arrow object
```
