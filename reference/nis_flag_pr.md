# Add procedure prefix flags

Each procedure slot is checked separately, with the same prefix rules,
byte for byte comparison, and `system` semantics as
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md).
`"icd10"` reads `I10_PR1`, ...; `"icd9"` (experimental) reads `PR1`, ...
Prefixes only match slots of the chosen system, so a flag over a mixed
2015 query is `FALSE` on discharges coded in the other system.

## Usage

``` r
nis_flag_pr(
  .data,
  ...,
  position = c("any", "principal"),
  system = c("icd10", "icd9")
)
```

## Arguments

- .data:

  A data frame or lazy Arrow query.

- ...:

  Named flag definitions, such as `ablation = "02L"`.

- position:

  Slots to check: all slots or the principal slot only.

- system:

  Code system of the slots to check: `"icd10"` (default) or `"icd9"`
  (experimental, NIS 2012 to Q3 2015).

## Value

`.data` with one logical column per named definition.

## Examples

``` r
nis <- nis_open(nis_example(years = 2019:2020))
nis |>
  nis_flag_pr(ablation = "02L") |>
  dplyr::count(ablation) |>
  dplyr::collect()
#> # A tibble: 2 × 2
#>   ablation     n
#>   <lgl>    <int>
#> 1 FALSE      144
#> 2 TRUE        48
```
