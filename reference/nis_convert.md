# Convert a NIS file to annual Parquet

Convert a NIS file to annual Parquet

## Usage

``` r
nis_convert(path, dir, encoding = NULL)
```

## Arguments

- path:

  Path to one annual NIS Stata (`.dta`), SAS (`.sas7bdat`), or SPSS
  (`.sav`) file with a numeric `YEAR` column, or one HCUP fixed-width
  `NIS_<year>_Core.ASC` file from 2012 through 2024.

- dir:

  Existing directory in which to create `NIS_<year>.parquet/`.

- encoding:

  Source encoding override passed to haven. The default uses the
  reader's format-specific encoding. Use `"latin1"` for a legacy Stata
  file known to use Latin-1.

## Value

The path of the annual Parquet directory, invisibly.

## Details

Conversion reads bounded batches and writes zstd-compressed Parquet
parts in source order. All records must have the same year, which must
agree with the year in filenames starting with `NIS_<year>`. Invalid
UTF-8 or malformed ICD slot values stop conversion. Blank codes and
HCUP's `invl` and `incn` codes are accepted.

Populated code slots must match the release's coding era. For 2015,
provide the discharge quarter or the corresponding diagnosis and
procedure version column. Later SAS and SPSS batches can require
rescanning the source from the beginning. This keeps memory bounded but
increases conversion time as the file grows.

Native Core files use HCUP's published SAS layouts, including the 2019
and 2020 V2 layouts. HCUP numeric missing codes become Parquet nulls.
Character fields lose their right padding and blank fields become nulls.
Use a consistent LF or CRLF line ending throughout the file. The 2015
native Core file contains no diagnosis or procedure slots. The Core
converter does not join the separate 2015 diagnosis and procedure groups
or other supplementary HCUP files.

The annual directory is published after validation and is never
overwritten.
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
checks converted data against the HCUP annual release statistics by
default.

## See also

Other data-access:
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md),
[`nis_label()`](https://msaadasif.github.io/easyNIS/reference/nis_label.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)

## Examples

``` r
if (requireNamespace("haven", quietly = TRUE)) {
  dir <- tempfile()
  dir.create(dir)
  path <- file.path(dir, "NIS_2020.dta")
  haven::write_dta(data.frame(YEAR = 2020L, I10_DX1 = "I509"), path)
  nis_convert(path, dir)
  nis_open(dir, check_release = FALSE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmppvTgxv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmppvTgxv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> # A query:  ?? x 2
#> # Database: DuckDB 2.0.1 [unknown@Linux 7.0.0-1018-aws:R 4.6.2/:memory:]
#>   I10_DX1  YEAR
#>   <chr>   <int>
#> 1 I509     2020
```
