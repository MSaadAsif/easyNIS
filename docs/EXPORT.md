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
- `format` is `"csv"` or `"html"`.
- `digits` must be `NULL` for CSV, which always writes exact values. For HTML
  it is `NULL` for exact values or a whole number from 1 to 15 giving
  significant digits for the estimate, SE and interval bounds. Counts,
  degrees of freedom and confidence levels are never rounded.
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
the review provenance or the HTML export, which records the policy. Spreadsheet
programs can interpret a label beginning with `=`, `+`, `-` or `@` as a
formula; easyNIS writes labels unchanged, so caller labels must be reviewed
before a CSV is opened in such a program.

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
an existing file and explicit replacement.
