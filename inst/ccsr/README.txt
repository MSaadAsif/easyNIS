AHRQ HCUP Clinical Classifications Software Refined (CCSR)

releases.csv records the version, release date, official download URL, and
counts of distinct codes, categories, and code-category pairs by release.

map.parquet contains one row per type, version, ICD-10 code, and assigned
category. Diagnosis default fields are Y for default, N for non-default,
and X for unacceptable as a principal or first-listed diagnosis. They
are missing for procedures and releases predating each default field.

categories.parquet contains one description per type, version, and category.
Workbook descriptions come from the CCSR Categories sheet. In the v2025.1
procedure workbook, this resolves an inconsistent ADM022 mapping-row label
while preserving the category code assigned in the mapping sheet.

The v2025.1 diagnosis and procedure mappings both cover ICD-10 codes from
October 2015 through September 2025. See the package COPYRIGHTS file for
attribution and the release archive for AHRQ's documentation.
https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccsr_archive.jsp
