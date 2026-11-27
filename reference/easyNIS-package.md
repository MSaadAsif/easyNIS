# easyNIS: Tidy Workflows for the National Inpatient Sample

Pipe-friendly tools for opening annual Healthcare Cost and Utilization
Project National Inpatient Sample Parquet files, flagging diagnosis and
procedure codes, looking up user-supplied CCSR codes, adding
experimental Elixhauser indicators, preparing designs and weights with
the 'survey' package, applying supported HCUP labels, adjusting charges
and costs, and reviewing disclosure risks. The Agency for Healthcare
Research and Quality provides information on the NIS and how to obtain
it at <https://hcup-us.ahrq.gov/nisoverview.jsp>. Experimental methods
and annual-layout assumptions are not independently verified or
scientifically approved.

## Details

Use
[`nis_open()`](https://msaadasif.github.io/easyNIS/reference/nis_open.md)
to open annual National Inpatient Sample (NIS) data as a lazy DuckDB
table,
[`nis_flag_dx()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_dx.md)
or
[`nis_flag_pr()`](https://msaadasif.github.io/easyNIS/reference/nis_flag_pr.md)
to define a cohort, and
[`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
to prepare a survey design. Use
[`nis_suppress()`](https://msaadasif.github.io/easyNIS/reference/nis_suppress.md)
to review tables for disclosure risk before sharing.

Start with the simulated files from
[`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
and the [Getting started
guide](https://msaadasif.github.io/easyNIS/articles/getting-started.html).
For licensed data, see the [AHRQ HCUP NIS
overview](https://hcup-us.ahrq.gov/nisoverview.jsp) for documentation
and access.

## See also

Useful links:

- <https://github.com/MSaadAsif/easyNIS>

- <https://msaadasif.github.io/easyNIS/>

- Report bugs at <https://github.com/MSaadAsif/easyNIS/issues>

## Author

**Maintainer**: Muhammad Saad <msaadasif.md@gmail.com>
([ORCID](https://orcid.org/0000-0002-1792-2357))

Authors:

- Muhammad Saad <msaadasif.md@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-1792-2357))

- Ali Salman ([ORCID](https://orcid.org/0009-0001-1102-226X))
  (project_role: co-maintainer)
