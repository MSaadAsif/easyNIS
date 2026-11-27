# Attach an annual NIS companion to Core discharges

Attach an annual NIS companion to Core discharges

## Usage

``` r
nis_join_companion(.data, path, component, columns)
```

## Arguments

- .data:

  A lazy Core query from
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
  including its linkage fields.

- path:

  Directory containing Parquet for one companion component, using the
  annual or Hive layout accepted by
  [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).
  Keep Core and each companion in separate directories, with parts from
  the same release.

- component:

  One of `"hospital"`, `"severity"`, or `"dx_pr_grps"`.

- columns:

  Character vector of companion fields to add. Names are matched
  case-insensitively using DuckDB's identifier rules. Choose fields with
  names distinct from fields in `.data`.

## Value

A lazy DuckDB-backed Core query with the requested columns added.

## Details

Hospital uses `YEAR` and `HOSP_NIS`. Severity and Diagnosis and
Procedure Groups use `YEAR` and `KEY_NIS`. Include companion parts for
every year opened in `.data`. A field supplied only in some of those
years is missing in the others. A discharge without a matching companion
row is retained with missing companion values.

DuckDB checks for missing, duplicate, or incompatible companion keys
before constructing the left join. Uniqueness in the Core key types
guarantees exactly one output row per input discharge. Keep both sets of
Parquet files in place until the lazy query is evaluated.

Use hospital characteristics to describe discharges and compare
discharge outcomes. The joined rows and weights still represent
discharges. The Hospital file's `TOTAL_DISC` counts sampled discharges
and is excluded from this helper. HCUP's post-2011 design does not
support estimating individual hospital volumes.

## See also

[Opening NIS
data](https://msaadasif.github.io/easyNIS/reference/articles/opening-data.md),
[HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp).

## Examples

``` r
path <- tempfile()
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeQiwPn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
write_component <- function(component, fields) {
  folder <- file.path(path, component)
  dir.create(folder, recursive = TRUE)
  file <- DBI::dbQuoteString(con, file.path(folder, "NIS_2020.parquet"))
  DBI::dbExecute(con, paste0("COPY (SELECT ", fields, ") TO ", file, " (FORMAT PARQUET)"))
}
write_component("core", "2020 AS YEAR, 1 AS KEY_NIS, 7 AS HOSP_NIS")
#> [1] 1
write_component("hospital", "7 AS HOSP_NIS, 2 AS HOSP_BEDSIZE")
#> [1] 1
DBI::dbDisconnect(con, shutdown = TRUE)
nis_open(file.path(path, "core"), check_release = FALSE) |>
  nis_join_companion(file.path(path, "hospital"), "hospital", "HOSP_BEDSIZE") |>
  dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeQiwPn/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 1 × 4
#>   HOSP_NIS KEY_NIS  YEAR HOSP_BEDSIZE
#>      <int>   <int> <int>        <int>
#> 1        7       1  2020            2
```
