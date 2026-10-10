# Experimental table export

This is the first bounded NIS-020 increment. It writes the presentation of one
`nis_disclosure_review` to CSV or HTML using base R only. Word output, which
needs optional rendering packages and visual layout inspection, and export of
regression tables, which have no disclosure review yet, remain separate
increments. An exported file is a candidate for human publication review; it
does not certify a manuscript or approve annual support.

## Interface

`nis_export_table(review, path, format, digits, overwrite)`

- `review` is an experimental `nis_disclosure_review`. Descriptive tables,
  regression tables and other objects are refused, so unreviewed values have
  no export path. The review is rechecked before writing: `presentation` must
  have exactly its documented columns in order, one row per table row with
  matching IDs, labels, statistics, units and estimands, valid statuses, `NA`
  estimate, SE, interval and count on every suppressed row, and shown values
  identical to the reviewed numeric table. A modified review is refused
  rather than exported.
- `path` is one file path whose extension matches `format`
  (case-insensitive). Its directory must exist.
- `format` is `"csv"` or `"html"`.
- `digits` must be `NULL` for CSV, which always writes exact values. For HTML
  it is `NULL` for exact values or a whole number from 1 to 15 giving
  significant digits for the estimate, SE and interval bounds. Counts,
  degrees of freedom and confidence levels are never rounded.
- `overwrite` is `TRUE` or `FALSE`. An existing file is replaced only when it
  is `TRUE`.

The file is written to a temporary file in the target directory and then
renamed, so a failed call leaves no partial output and preserves an existing
file. The call returns the normalized path invisibly. It never modifies the
review.

## CSV

The CSV contains the 13 presentation columns in order, UTF-8 encoded, with
`\n` line endings and a header row. Text columns are quoted, with embedded
quotes doubled. Numeric values use the shortest of 15, 16 or 17 significant
digits that parses back to the identical double, so `utils::read.csv()`
recovers every shown value exactly. Infinite degrees of freedom are written as
`Inf`. Suppressed cells are empty, and `disclosure_status` records whether the
row was shown or suppressed as primary or complementary. Audit counts, missing
counts, supplied counts, hospital counts and weighted denominators are never
written.

The CSV is a data interchange file and carries no policy notes. Keep it with
the review provenance or the HTML export, which records the policy. Spreadsheet
programs can interpret a label beginning with `=`, `+`, `-` or `@` as a
formula; easyNIS writes labels unchanged, so caller labels must be reviewed
before a CSV is opened in such a program.

## HTML

The HTML file is a standalone UTF-8 document with no scripts or external
resources. Every caller-supplied text value is escaped. The table shows the
label, statistic, unit, estimand, estimate, SE, interval with its confidence
level, degrees of freedom, unweighted discharges and disclosure status.
Suppressed rows show `Suppressed` in every value cell and state primary or
complementary suppression; no hidden value appears anywhere in the document.

Notes under the table state that the table is experimental and not analysis
ready, that counts are unweighted included discharges rather than patients,
that estimates are survey weighted, the suppression range, zero policy,
hospital minimum and number of declared margins, that complementary
suppression is a bounded greedy procedure and that undeclared relations and
other publications need human review, and whether values are exact or rounded
to the stated significant digits.

## Acceptance cases

Verification must use the installed public API on invented data. Cases cover
exact CSV round trips of shown values including infinite df, empty suppressed
cells for primary and complementary rows, absent audit fields, HTML escaping of
markup, quotes and ampersands in labels and units, non-ASCII labels in both
formats, commas, quotes and newlines in CSV text, rounding to significant
digits without changing the review, the absence of hidden values from HTML,
refusal of unreviewed descriptive tables, regression tables and modified
reviews (including a revealed suppressed value and a changed shown value),
argument errors, extension mismatch, a missing directory, refusal to replace
an existing file and explicit replacement.
