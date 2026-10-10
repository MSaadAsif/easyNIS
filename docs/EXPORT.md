# Experimental table export

NIS-020 writes the presentation of one `nis_disclosure_review` to CSV or HTML
using base R, or to Word using the optional officer package. Export of
regression tables, which have no disclosure review yet, remains a separate
increment. An exported file is a candidate for human publication review; it
does not certify a manuscript or approve annual support.

## Interface

`nis_export_table(review, path, format, digits, formula_text, overwrite)`

- `review` is an experimental `nis_disclosure_review`. Descriptive tables,
  regression tables and other objects are refused, so unreviewed values have
  no export path. Before writing, the table's estimate, SE, interval, df and
  confidence columns must equal the retained `nis_estimate` results, and the
  review is recomputed from its table under its recorded policy. The complete
  recomputed review, including presentation, audit and provenance, must be
  identical to the supplied one. Edits to the presentation, audit, provenance
  or the table's estimate columns, alone or consistently across them, such as
  a relabeled status with revealed values, a changed count or estimate, or a
  different recorded policy, are refused. Recomputation cannot authenticate
  the retained results themselves, including their estimates and the survey
  design data from which suppression counts are taken; an object whose
  retained results were altered can still pass. The check ensures the file
  matches what the review procedure produces from the retained results. Each
  export repeats the complete disclosure review, so its cost grows with the
  table and its margins.
- `path` is one file path whose extension matches `format`
  (case-insensitive). Its directory must exist.
- `format` is `"csv"`, `"html"` or `"docx"`.
- `digits` must be `NULL` for CSV, which always writes exact values. For HTML
  and Word it is `NULL` for exact values or a whole number from 1 to 15 giving
  significant digits for the estimate, SE and interval bounds. Counts,
  degrees of freedom and confidence levels are never rounded.
- `formula_text` must be `NULL` for HTML and Word. For CSV it is `"refuse"`,
  `"prefix"` or `"keep"` and controls text cells that begin with `=`, `+`,
  `-`, `@`, their full-width forms, a tab, a carriage return or a line feed;
  see below. It has no default.
- `overwrite` is `TRUE` or `FALSE`. An existing file is replaced only when it
  is `TRUE`.

The file is written to a temporary file in the target directory and then
renamed, so a failed call leaves no partial output and preserves an existing
file. The existence check precedes the rename, so a file created at `path` by
another process during the call can still be replaced. The call returns the
normalized path invisibly. It never modifies the review.

## CSV

The CSV contains the 13 presentation columns in order, UTF-8 encoded, with
`\n` line endings and a header row. Text columns are quoted, with embedded
quotes doubled. Whole numbers up to 2^53 are written in full and other values
with 17 significant digits, which identifies each double exactly for any
correctly rounding parser, including `utils::read.csv()`. Values are therefore
long; a confidence level of 0.9 is written `0.90000000000000002`. Infinite
degrees of freedom are written as `Inf`. Suppressed cells are empty, and `disclosure_status` records whether the
row was shown or suppressed as primary or complementary. Audit counts, missing
counts, supplied counts, hospital counts and weighted denominators are never
written. Text is quoted but `utils::read.csv()` still converts a label of
`NA` to a missing value unless `na.strings` is changed.

The CSV is a data interchange file and carries no policy notes. Keep it with
the review provenance or the HTML export, which records the policy.

Spreadsheet programs can run a cell as a formula when it begins with `=`, `+`,
`-` or `@`, their full-width forms (U+FF1D, U+FF0B, U+FF0D, U+FF20), a tab, a
carriage return or a line feed, and a formula can fetch external content or
start programs. The set follows the OWASP CSV injection guidance; other
spreadsheet behavior is not tested. Every text column is checked, including caller ids, labels and units.
Numeric columns are written as numbers and are not affected, so a negative
estimate stays numeric. `formula_text` chooses the handling:

- `"refuse"` stops before writing and names the column and row id of each
  such cell, without repeating the text.
- `"prefix"` writes each such cell with a leading `'`, which spreadsheet
  programs display as text. The prefix changes the exported text: reading the
  file back returns `'=...` rather than the caller's label.
- `"keep"` writes the text unchanged, for files read only by data tools. The
  caller then accepts the spreadsheet risk.

Text that only contains these characters later, such as `Stay - days`, is
unaffected. A quoted carriage return is valid CSV, but `utils::read.csv()`
splits it into separate cells, which also shifts later rows.

## HTML

The HTML file is a standalone UTF-8 document with no scripts or external
resources. Every caller-supplied text value is escaped. The table shows the
label, statistic, unit, estimand, estimate, SE, interval bounds, degrees of
freedom, unweighted discharges, disclosure status and confidence level.
Confidence levels have a separate column on the 0 to 1 scale, written with
17 significant digits so they parse back to identical doubles.
Suppressed rows show `Suppressed` in the estimate, SE, interval and count
cells and state primary or complementary suppression; their df and confidence
level are the caller's table-wide choices and remain visible. No hidden value
appears anywhere in the document.

Notes under the table state that the table is experimental and not analysis
ready, that counts are unweighted included discharges rather than patients,
that estimates are survey weighted, the suppression range, zero policy,
hospital minimum and number of declared margins, that complementary
suppression is a bounded greedy procedure, that larger combinations of declared
margins remain unchecked and that undeclared relations and
other publications need human review, and whether values are exact or rounded
to the stated significant digits.

## Word

Word output needs officer 0.5.0 or later, which easyNIS suggests but does not
import, together with its xml2 dependency. Without it the call stops before
writing and names `install.packages("officer")`, CSV and HTML. The document
contains the HTML caption as a title, the same eleven header and body cells
with the same `Suppressed` and status text, and the same notes as paragraphs.
Values are written as text; every text node in the document is one of these
caption, header, cell or note strings, so no hidden value is present. Word
cannot store control characters other than tab, carriage return and line
feed, or the noncharacters U+FFFE and U+FFFF; a label or unit containing one
is refused, naming the column and row id, before writing. officer writes a
carriage return, alone or before a line feed, as a line feed, and Word
displays line breaks and tabs in a cell as white space.

The page is US Letter landscape with half-inch margins. Table cells use an
8-point paragraph style with 0.04-inch left and right cell margins, header
cells are bold and repeat on each page, text columns are left aligned and
numeric columns right aligned, and no row splits across pages. Column widths
estimate 0.07 inch per character of each column's longest word, counting at
most 24 characters. When the longest words fit in the 10-inch text width,
the spare width is shared in proportion and no word breaks. Otherwise header
words and package text (statistic, estimand, df, `Suppressed`, status and
confidence level) keep their full width, and caller labels and units and
estimates, SEs, interval bounds and counts share the rest, wrapping and
breaking words within their cells. Exact 17-digit values usually need this
second case. A row taller than a page would still have to break. The layout
was inspected visually after conversion to PDF by Microsoft Word for exact
and three-digit tables and a 45-row table with long labels; other word
processors are not tested.

## Acceptance cases

Verification must use the installed public API on invented data. Cases cover
exact CSV round trips of shown values including infinite df, empty suppressed
cells for primary and complementary rows, absent audit fields, HTML escaping of
markup, quotes and ampersands in labels and units, non-ASCII labels in both
formats, commas, quotes and newlines in CSV text, rounding to significant
digits without changing the review, the absence of hidden values from HTML,
exact visible confidence levels even when every row is suppressed, including
levels close to one that would round to 100 percent, refusal of unreviewed
descriptive tables, regression tables and modified
reviews (including a revealed suppressed value, a status relabeled
consistently with revealed values, a forged policy, consistently changed
counts and estimates, and factor statuses),
argument errors, extension mismatch, a missing directory, refusal to replace
an existing file and explicit replacement. Formula-text cases cover every
leading character in labels under all three policies, plus `@` and full-width
`@` ids and `-` and full-width `-` units, an exact refusal message that names
every affected cell and no other, no file after refusal, internal hyphens,
and rejection of a CSV policy for HTML. Word cases compare every header, body
cell and note with the HTML export for exact and rounded values, require every
text node in every XML part to be one of those strings and no exact hidden
estimate, SE or bound, check escaped markup, the landscape page, unsplittable
rows, an upper-case extension and an unchanged review, refuse a bell,
vertical tab, U+FFFE and U+FFFF with an exact message and no file,
accept tab and line breaks, reject a CSV policy, invalid digits, a mismatched
extension and an existing file, and give the install guidance without
writing when officer is unavailable. The installed smoke compares Word and
HTML cells for the subtotal reproduction.
