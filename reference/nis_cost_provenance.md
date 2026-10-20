# Read cost adjustment provenance

Returns the metadata recorded by
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
or
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
when cost adjustment was requested. Data frame operations may drop
custom attributes; call this on the direct
[`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
result or on the survey design returned by
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Usage

``` r
nis_cost_provenance(x)
```

## Arguments

- x:

  A data frame returned by
  [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  or a survey design returned by
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

## Value

A list describing the charge and CCR fields, CPI-U source and base year,
annual multipliers, invalid CCR and missing charge counts, and output
meanings. Returns `NULL` when no cost adjustment provenance is present.
