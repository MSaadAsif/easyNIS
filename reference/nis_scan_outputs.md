# Scan a publication folder for disclosure risks

Check CSV, TSV, XLSX, HTML, Markdown, text, and DOCX files in a folder
and its subfolders. The scan flags known HCUP identifier names and
potential unmasked counts of 1 through 10 in recognizable count columns
or explicit statements such as "n = 5" and "5 discharges".

## Usage

``` r
nis_scan_outputs(path, error = FALSE)
```

## Arguments

- path:

  Directory containing the files you intend to publish.

- error:

  If `TRUE`, stop with class `easyNIS_output_scan` when any finding is
  present. The condition carries a `findings` data frame.

## Value

A data frame with `file` (relative path), `location` (file, document
part, sheet, table or column), `issue` (`restricted_identifier`,
`small_count` or `scan_error`), and `field` (the recognized identifier
name, or `NA`). A finding can represent several matches in one location.
Cell contents and reader diagnostics are omitted.

## Details

This check is heuristic. An identifier name can appear in a legitimate
methods description. Review unsupported files (including images and
PDFs), renamed identifiers, unfamiliar table layouts, and counts
recoverable from totals, percentages, or other releases by hand.

XLSX uses readxl. HTML and DOCX use xml2, and Markdown also uses
commonmark. A supported file that cannot be read, including when an
optional reader is missing, produces a `scan_error`.

## See also

[Check disclosure before sharing
results](https://msaadasif.github.io/easyNIS/articles/disclosure.html)

Other disclosure:
[`nis_cell_counts()`](https://msaadasif.github.io/easyNIS/reference/nis_cell_counts.md),
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)

## Examples

``` r
folder <- tempfile()
dir.create(folder)
writeLines(c("group,n", "A,3", "B,20"), file.path(folder, "table.csv"))
nis_scan_outputs(folder)
#>        file      location       issue field
#> 1 table.csv file column 2 small_count  <NA>
unlink(folder, recursive = TRUE)
```
