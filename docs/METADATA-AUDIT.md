# Annual metadata audit tools

The annual audit is pending. The public Core specifications for
[2017](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/FileSpecifications_NIS_2017_Core.TXT)
and [2022](https://hcup-us.ahrq.gov/db/nation/nis/tools/stats/FileSpecifications_NIS_2022_Core.TXT)
were inspected through the web reader on 2026-10-08. Their column guides differ.
For example, the field-name range is 41–69 in 2017 and 42–70 in 2022.
The previous updater applied the latter range to every year. The new reader uses
each specification's column guide.

Workstation downloads timed out in earlier continuations. On 2026-10-13,
[retrieval run 38441703963](https://github.com/MSaadAsif/easyNIS/actions/runs/38441703963)
received all six original Core specification bodies from the canonical official
HTTPS host. After artifact transfer, every body/header length and SHA-256
matched its remote receipt. Original bodies, raw HTTP headers and acquisition
receipts remain in ignored local evidence; parsed Core facts are recorded in
`inst/metadata/modern-layouts.csv` with provisional review status. Human source
review and separate component, missing-value and conversion audits remain pending.

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
The absence of a suffix is recorded as `unspecified`, rather than inferred V1,
in `specification_revision`. This field describes the requested specification
filename, not an authenticated revision of a licensed data conversion.

The reader checks the dataset header, row years and dataset filenames,
header counts, column guides, sequential field numbers, unique names, record
positions, decimal precision, required numeric structural fields, and contiguous
seven-character diagnosis and procedure slots. Labels and missing-value meanings
are not extracted. In both official V2 specifications, the dataset header and
row filenames are `NIS_2019_CORE` or `NIS_2020_CORE`, without `_V2`.
`dataset_name` retains this identity separately from `specification_revision`.
The official [specifications index](https://hcup-us.ahrq.gov/db/nation/nis/nisfilespecs.jsp)
lists suffixed V2 dataset names for those years. This registry preserves the
downloaded specification body's header/row identity; it does not resolve that
difference or establish the filename of a licensed source/conversion.
The earlier parser appended `_V2` to the expected dataset and rejected both
valid sources. The corrected parser requires the exact unsuffixed Core dataset
for the requested year; invented suffixed or wrong-year datasets are refused.
These checks validate the specification's internal structure;
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

## Retrieve original response bytes on GitHub

`tools/fetch-official-layouts.py` tries the canonical official host and then
the alternate official `hcup-ts.ahrq.gov` host for each Core specification.
It requires Python 3 and curl. Every request has a 20-second total limit,
five-second connection limit and at most five HTTPS redirects. Run it with a
new ignored output directory; existing directories are refused:

```sh
python -B -m unittest discover -s tools/tests -p test_fetch_official_layouts.py -v
python -B tools/fetch-official-layouts.py .audit/official-layouts-new
```

The separate `Retrieve public official layouts` workflow runs these offline
tests and retrieval on relevant pull requests or manual dispatch. It has no
schedule, reads no licensed files, and has read-only repository permissions.
After it reaches main, request an on-demand run with
`gh workflow run official-layouts.yaml`. Its `official-core-response-bytes`
artifact retains only this job's response bodies, raw response headers and
JSON manifest for 14 days. Download a completed run with
`gh run download RUN_ID -n official-core-response-bytes -D .audit/official-transfer-RUN_ID`.
See GitHub's [artifact download instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).

The manifest records each requested/final URL, UTC start/completion times,
HTTP status, curl exit/error and the byte lengths and SHA-256 hashes of saved
bodies and headers. Failed HTTP responses and partial transport bodies remain
evidence, with an explicit failure outcome. A successful HTTP 200 response
ending on either official HTTPS host is marked `downloaded`; this says nothing
about its content. HTML error pages can return 200. The artifact job can succeed
even when every source request fails: inspect the manifest, rather than using
the workflow conclusion as acquisition evidence.

Before promoting a downloaded body into the ignored cache, verify its SHA-256
and length after transfer and run `parse_core_layout()` for its declared year.
The revision suffix belongs to the specification filename. Preserve the body
unchanged when copying it to the manifest's
`cache_filename`; retain the manifest and headers alongside local evidence.
Do not copy failed or unparsed bodies. Then run the cached-only updater.
The fetcher never populates the cache or changes the registry, support matrix
or conversion status. A parsed Core specification still needs human source
review and the separate component/missing-value audit below.

## Remaining acceptance work

The inventory's `year_hint` uses only complete `NIS_YYYY.parquet` filenames,
case-insensitively. Parent directory names, filename prefixes and extra suffixes
do not supply a hint. A hint is not an inspected or validated `YEAR` value and
does not establish annual support.

Inventory schemas describe the columns and types stored in each file. Automatic
Hive partition discovery is disabled, so folders such as `YEAR=2017` neither
add columns nor override file column types. The importer uses the same policy.
Top-level column names come from the physical parquet schema and retain exact
duplicates and case collisions that SQL queries would rename. Positions and
DuckDB-interpreted types follow file order. Nested children are not additional
top-level columns. An inventory does not establish importability; the importer
still refuses case-insensitive field collisions and nested fields.

The parquet inventory receipt retains `writer_metadata`, the raw `created_by`
footer string. It is a lead for tracing the writer, not authenticated conversion
history. It does not establish source revisions, component joins, prefiltering,
labels or special missing-value preservation; those statuses remain unverified.
The inventory also records `compression_metadata`, the distinct column-chunk
codecs reported by each file, sorted and separated by semicolons. A converter's
declared compression setting can differ from the file's observed codec. The
receipt records the latter without inferring which settings or script ran.

1. Review the saved official Core specifications and provisional registry
   for all six years. Audit Hospital, Severity, and Diagnosis
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
