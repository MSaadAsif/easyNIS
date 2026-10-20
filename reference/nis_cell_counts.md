# Count discharges and contributing hospitals by cell

Produces the unweighted discharge and distinct hospital counts used by
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md).
Hospital identity is the year-scoped pair `YEAR` and `HOSP_NIS`,
matching
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
The input can be a record-level data frame or the result of
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
Rows with invalid hospital identity are rejected so counts cannot
silently understate disclosure risk.

## Usage

``` r
nis_cell_counts(.data, by)
```

## Arguments

- .data:

  Record-level data frame or result of
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).

- by:

  Character vector of cell-defining columns.

## Value

A data frame with the columns in `by`, `n` (unweighted discharges), and
`hospitals` (distinct year-scoped hospitals).

## Examples

``` r
records <- data.frame(
  YEAR = c(2020, 2020, 2020), HOSP_NIS = c(1, 1, 2), group = c("A", "A", "A")
)
nis_cell_counts(records, by = "group")
#> # A tibble: 1 × 3
#>   group     n hospitals
#>   <chr> <int>     <int>
#> 1 A         3         2
```
