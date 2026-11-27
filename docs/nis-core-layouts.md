# HCUP Core layout provenance

`inst/extdata/nis-core-layouts.csv` records the starting byte, field width,
implied decimal places, and numeric missing tokens from each annual HCUP
SAS Core load program. A blank value in `decimals` identifies a character
field. Each row records the URL of its load program. The 2019 and 2020
layouts come from the V2 programs. The 2015 Core file excludes the
quarter-specific Diagnosis and Procedure Groups files.
[HCUP Nationwide SAS load programs](https://hcup-us.ahrq.gov/db/nation/sasloadprog.jsp)

From PowerShell in the repository root, fetch the public programs using
the same proxy used for the original extraction.

```powershell
$cache = "local/loop/nis-core-layouts"
New-Item -ItemType Directory -Force $cache | Out-Null
foreach ($year in 2012..2024) {
  $revision = if ($year -in 2019, 2020) { "_V2" } else { "" }
  $name = "SASLoad_NIS_${year}_Core${revision}.SAS"
  $url = "https://hcup-us.ahrq.gov/db/nation/nis/tools/pgms/$name"
  curl.exe -fLsS --retry 3 "https://r.jina.ai/$url" -o "$cache/$name.txt"
  if ($LASTEXITCODE -ne 0) { throw "Could not download $name" }
}
Rscript --vanilla tools/generate-nis-core-layouts.R $cache
```

The generator checks that field positions are unique and contiguous,
that informats account for each byte of the declared record length, and
that every layout includes `YEAR`. Its transcript records the source URL
and downloaded document checksum for each year. The generated CSV
contains layout metadata only.
