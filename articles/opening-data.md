# Opening NIS data

## Use the synthetic fixture

[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
creates an invented Parquet dataset with familiar NIS fields. It is
suitable for learning and examples, not for estimating national
quantities.

``` r

path <- nis_example(years = 2019:2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis <- nis_open(path)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis |> dplyr::count(YEAR) |> dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
#> 2  2019    96
```

The result reports the number of synthetic rows in each selected year.

easyNIS does not bundle real NIS data. The HCUP [Nationwide Data Use
Agreement](https://hcup-us.ahrq.gov/team/NationwideDUA.jsp) advises
avoiding publication of values of 1–10 in text and tables. Separately,
the [Checklist for Working with the
NIS](https://hcup-us.ahrq.gov/db/nation/nis/nischecklist.jsp) says at
least two hospitals must contribute to each cell.
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
masks counts at or below `threshold` (10 by default), applies
complementary suppression by default for data frames, and, when given
hospital counts from
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md),
masks cells from fewer than two hospitals. Use
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
to try the workflow without licensed data.

## Convert source data to Parquet

[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md)
reads annual Stata (`.dta`), SAS (`.sas7bdat`), and SPSS (`.sav`) files
using haven. Supply a file with a numeric `YEAR` column and an existing
output directory. The converter reads bounded batches, checks encoding,
code syntax and row counts, and publishes the annual Parquet directory
only after all checks pass. For a legacy Stata file known to use
Latin-1, pass `encoding = "latin1"`. For 2015 files with populated ICD
slots, keep `DQTR` or the applicable `DXVER` and `PRVER` indicators so
the converter can check the coding era. Later SAS and SPSS batches can
rescan earlier records. This keeps memory bounded and can make wide,
compressed files slow to convert.

``` r

converted <- tempfile()
dir.create(converted)
source <- file.path(converted, "NIS_2020.dta")
haven::write_dta(data.frame(YEAR = 2020L, I10_DX1 = "I509"), source)
nis_convert(source, converted)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_open(converted, check_release = FALSE) |> dplyr::collect()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 1 × 2
#>   I10_DX1  YEAR
#>   <chr>   <int>
#> 1 I509     2020
```

The invented example skips the release comparison. Leave it enabled for
files representing an HCUP release.

For a native fixed-width HCUP Core file, unzip the download and pass the
`NIS_<year>_Core.ASC` file to
[`nis_convert()`](https://msaadasif.github.io/easyNIS/reference/nis_convert.md).
The converter uses HCUP’s 2012–2024 Core layouts, including the 2019 and
2020 V2 specifications. The 2015 Core file has no diagnosis or procedure
slots. To analyze those fields, prepare a joined annual statistical file
from the Core and quarter-specific Diagnosis and Procedure Groups files
before converting it. [HCUP Nationwide SAS load
programs](https://hcup-us.ahrq.gov/db/nation/sasloadprog.jsp)

``` r

converted_core <- tempfile()
dir.create(converted_core)
core <- file.path(converted_core, "NIS_2015_Core.ASC")
record <- paste0(strrep(" ", 35), "00001", strrep(" ", 15), "0001",
                 strrep(" ", 21), "2015", "  ")
writeLines(record, core)
nis_convert(core, converted_core)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
nis_open(converted_core, check_release = FALSE) |>
  dplyr::select(YEAR, HOSP_NIS, NIS_STRATUM) |>
  dplyr::collect()
#> Experimental: years before 2016 store ICD-9-CM codes in DX1, PR1, ... slots.
#> ℹ Flag them with `system = "icd9"`; 2015 mixes ICD-9 (Q1-Q3) and ICD-10 (Q4)
#>   slots.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> This message is displayed once per session.
#> # A tibble: 1 × 3
#>    YEAR HOSP_NIS NIS_STRATUM
#>   <int>    <int>       <int>
#> 1  2015        1           1
```

## Select years and columns

`years` limits which annual files are opened. Use
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html)
to narrow what a later collection needs; lazy operations are evaluated
when collected.

``` r

nis_open(path, years = 2020) |>
  dplyr::select(YEAR, AGE, FEMALE, LOS) |>
  dplyr::collect() |>
  head()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A tibble: 6 × 4
#>    YEAR   AGE FEMALE   LOS
#>   <int> <dbl>  <int> <dbl>
#> 1  2020    28      1     2
#> 2  2020    35      0     3
#> 3  2020    42      1     4
#> 4  2020    49      0     5
#> 5  2020    56      1     6
#> 6  2020    63      0     7
```

The preview contains only the requested variables from the synthetic
2020 file. Mixed-case column names are normalized to upper case; already
lower-case names remain unchanged.

## Annual release checks

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
checks converted Core files by default. DuckDB compares the row count,
sum of `DISCWT`, and distinct `HOSP_NIS` count for each year against
HCUP’s Core Weighted and Hospital Weights summary statistics for
2012–2024. [HCUP NIS summary
statistics](https://hcup-us.ahrq.gov/db/nation/nis/nissummstats.jsp)

When those fields are present, missing `YEAR`, `YEAR` outside the opened
years, and nonpositive `NIS_STRATUM` values also warn. Warnings leave
the lazy query available. Files from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
still undergo these integrity checks and are excluded from the published
totals. If you open an intentional extract, set `check_release = FALSE`
to skip the check.

## Attach companion files

Keep Core, Hospital, Severity, and Diagnosis and Procedure Groups
Parquet in separate directories. Use the same annual or Hive layout in
each directory. Check the component availability and file splits for
each year, and use matching release revisions. [HCUP NIS File
Specifications](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp)

``` r

core <- nis_open(core_path, years = 2019:2020)
discharges <- core |>
  nis_join_companion(hospital_path, "hospital", "HOSP_BEDSIZE") |>
  nis_join_companion(severity_path, "severity", "APRDRG_SEVERITY")
```

Hospital linkage uses `YEAR` and `HOSP_NIS` because hospital IDs are
specific to each year. Severity and Diagnosis and Procedure Groups use
`YEAR` and `KEY_NIS`. Supply companion parts for every year opened in
Core, or open the years with the component you need. DuckDB checks the
companion keys and returns a lazy left join with one row per input
discharge. Unmatched discharges have missing companion values. [HCUP NIS
Description of Data
Elements](https://hcup-us.ahrq.gov/db/nation/nis/nisdde.jsp)

Use linked hospital characteristics to describe **discharges**. For
example, a discharge-weighted share by teaching status describes where
stays occurred. It does not estimate the share of hospitals that teach.
From 2012 onward, hospital sampling fractions are unavailable, so
neither counting rows nor summing discharge weights yields individual
hospital volume. `TOTAL_DISC` is itself a sampled discharge count and
cannot be attached through this helper. [HCUP guidance on hospital
volume
estimates](https://hcup-us.ahrq.gov/db/nation/nis/NIS_Introduction_2021.jsp#hospital-volume-estimates)

## Filter and project before collecting

[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
uses DuckDB’s native Parquet reader by default and returns a lazy dbplyr
table. `duckdb`, `dbplyr`, and `DBI` are required dependencies. Filter
and select before collecting when later analysis needs an in-memory data
frame. The default reader is unchanged; `reader = "arrow"` opts in to
the optional `arrow` package for reading Parquet files individually.

``` r

duck <- nis_open(path, years = 2020)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpijNuPC/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
duck |> dplyr::count(YEAR) |> dplyr::collect()
#> # A tibble: 1 × 2
#>    YEAR     n
#>   <int> <dbl>
#> 1  2020    96
```

This count is the same synthetic year summary, evaluated through DuckDB.

Arrow preserves source bytes in string columns, including malformed
UTF-8 bytes. It does not repair or automatically detect every invalid
string, and malformed values may still fail in downstream string
operations. Validate or repair text before analysis when those
operations are needed.

When converting HCUP ASCII files to Parquet, declare the source encoding
so string values are written as valid UTF-8. For example, convert
Latin-1 text to UTF-8 rather than writing bytes under the wrong encoding
label.

## Common pitfalls

> **Common pitfalls**
>
> - Opening all years and collecting all columns can require substantial
>   memory. Filter and select before collecting.
> - Survey-design preparation collects the selected design fields in R.
>   Keep the cohort and retained columns bounded before using
>   [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
> - [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
>   data are invented and should not be reported as NIS estimates.

See [Cohort
definitions](https://msaadasif.github.io/easyNIS/articles/cohorts.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
and
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md).

## Working with data larger than RAM

DuckDB scans the Parquet files in place. Filter rows and select fields
on the lazy query. Then collect a small summary, or write a large result
directly to a private Parquet file.
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
still needs enough R memory for the selected cohort, retained variables,
and survey design. Use a narrow `keep` to limit that cost. [DuckDB COPY
statement](https://duckdb.org/docs/stable/sql/statements/copy)

When a collect is estimated to need 20% of available physical memory,
easyNIS reports the estimated result size. At 50% or more, easyNIS
counts the result rows and stops the collect if the estimate still
crosses that threshold. This also applies to
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
tables and to easyNIS helpers that collect DuckDB results. Filter rows,
select fewer fields, or use a narrower cohort and `keep` in
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md).
Use `options(easyNIS.collect_prudence = FALSE)` to skip the check.
Cardinality and text widths are approximate. The check can also be
skipped automatically when DuckDB cannot estimate the result size.
Queries with SQL `PIVOT` skip the check because DuckDB may scan rows
while determining their output columns.

Set DuckDB options before calling
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md).
This example uses a low thread count and places spill files on a private
disk. Choose the memory and spill budgets for your machine and available
disk space.

``` r

options(easyNIS.duckdb_config = list(
  memory_limit = "4GB",
  threads = 2L,
  temp_directory = tempdir(),
  max_temp_directory_size = "40GB"
))
query <- nis_open(data_path, years = 2019:2022)
query |>
  dplyr::filter(AGE >= 18) |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(discharge_count = dplyr::n()) |>
  dplyr::collect()
```

To write a result on disk, set `private_parquet_path` to a file in your
private output directory and send the lazy query to DuckDB.

``` r

projection <- query |>
  dplyr::filter(AGE >= 18) |>
  dplyr::select(YEAR, AGE)
connection <- dbplyr::remote_con(projection)
statement <- dbplyr::sql_render(projection)
destination <- DBI::dbQuoteString(connection, private_parquet_path)
DBI::dbExecute(connection,
  paste0("COPY (", statement, ") TO ", destination, " (FORMAT PARQUET)"))
```

Use `preserve_insertion_order = FALSE` for memory-constrained scans or
exports whose result order is immaterial. Use an explicit sort when you
need a defined order. DuckDB’s memory limit controls its buffer manager.
R objects and some DuckDB operations can use additional memory. See the
[DuckDB workload tuning
guide](https://duckdb.org/docs/stable/guides/performance/how_to_tune_workloads).

Reuse a query for related summaries so they share one connection. The
memory and spill settings apply to each open connection. When an
analysis finishes, discard the query and any lazy tables derived from
it. Garbage collection releases the connection and removes its spill
directory. In a loop that opens many datasets, release each completed
query before opening the next one if disk or memory is tight.
