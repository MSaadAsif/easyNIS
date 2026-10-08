# Annual metadata audit tools

The annual audit is pending. The public Core specifications for
[2017](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/FileSpecifications_NIS_2017_Core.TXT)
and [2022](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/FileSpecifications_NIS_2022_Core.TXT)
were inspected through the web reader on 2026-10-08. Their column guides differ.
For example, the field-name range is 41–69 in 2017 and 42–70 in 2022.
The previous updater applied the latter range to every year. The new reader uses
each specification's column guide.

Direct download still timed out in this continuation. No source-byte snapshot,
checksum, or installed annual registry was produced. Web inspection informs the
parser; it does not replace the required saved source and author review.

## Run the updater

From the repository root, with R on the command path:

```r
testthat::test_dir("tools/tests", stop_on_failure = TRUE)
```

```sh
Rscript tools/update-layout-metadata.R
Rscript tools/update-layout-metadata.R --cached-only
```

The first command downloads missing Core specifications to the ignored
`docs/references/local/official-layouts/` cache. The second requires all six
cached files and performs no network requests. The expected filenames are
`FileSpecifications_NIS_YEAR_Core.TXT`, with `_V2` before `.TXT` for 2019
and 2020, as listed on the official
[file specifications page](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp).
The absence of a suffix is recorded as `unspecified`, rather than inferred V1.

The reader checks the dataset and revision header, row years and filenames,
header counts, column guides, sequential field numbers, unique names, record
positions, decimal precision, required numeric structural fields, and contiguous
seven-character diagnosis and procedure slots. Labels and missing-value meanings
are not extracted. These checks validate the specification's internal structure;
they do not establish the correctness of every published fact.

A download must pass parsing before it enters the cache. An invalid existing
cache fails without an automatic replacement. All requested years must pass
before the CSV is staged beside its destination and renamed into place.
Earlier valid cached downloads may remain after a later year fails, but the
previous registry stays intact. Tests cover this partial-batch case and byte
preservation of the existing registry. The tool restores the caller's timeout
option after success or failure.

Successful runs write `inst/metadata/modern-layouts.csv` with source URLs,
snapshot MD5 values, parse timestamps, structural counts and `provisional`
review status. A parse timestamp is not a retrieval timestamp. The runtime API
does not consume this development registry. Parsing never changes
`year-support.csv` or permits inference. The updater and its invented tests are
excluded from source packages and are checked separately in CI.

## Remaining acceptance work

1. Save the official Core specifications for all six years and inspect the
   provisional registry against them. Audit Hospital, Severity, and Diagnosis
   and Procedure Groups specifications independently, including availability.
2. Inspect official annual load formats and data-element notes for field-level
   special missing values, units, labels, applicability and revision corrections.
   The Core layout alone does not define those contracts.
3. Compare the licensed conversions locally with the reviewed source contracts.
   Establish aliases, merged-component history, prefiltering, derived-tool
   versions, and whether missing reasons or labels were lost. Store input paths
   and private receipts only in ignored storage.
4. Obtain Saad and Ali's review before promoting annual metadata or statistical
   methods. Build canonical transformations only from the resulting contracts.

Invented fixtures exercise parser behavior and rollback. They authenticate no
annual release, conversion, clinical phenotype, or survey calculation.
