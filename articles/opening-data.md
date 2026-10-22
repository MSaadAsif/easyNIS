# Opening NIS data

## Use the synthetic fixture

[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
creates an invented Parquet dataset with familiar NIS fields. It is
suitable for learning and examples, not for estimating national
quantities.

``` r

path <- nis_example(years = 2019:2020)
nis <- nis_open(path)
nis |> dplyr::count(YEAR) |> dplyr::collect()
#> # A tibble: 2 × 2
#>    YEAR     n
#>   <int> <int>
#> 1  2019    96
#> 2  2020    96
```

The result reports the number of synthetic rows in each selected year.

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

## Choose a query engine

Arrow is the default. `engine = "duckdb"` requires the optional `duckdb`
and `dbplyr` packages and returns a DuckDB-backed table. The current
flagging and design helpers support Arrow queries or data frames, so
collect a bounded subset before using a DuckDB result with those
helpers.

``` r

duck <- nis_open(path, years = 2020, engine = "duckdb")
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8cpuxe/duckdb
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

## Common pitfalls

> **Common pitfalls**
>
> - Opening all years and collecting all columns can require substantial
>   memory. Filter and select before collecting.
> - DuckDB support in
>   [`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
>   does not mean every downstream helper accepts DuckDB queries.
> - [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
>   data are invented and should not be reported as NIS estimates.

See [Cohort
definitions](https://msaadasif.github.io/easyNIS/articles/cohorts.md),
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md),
and
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md).
