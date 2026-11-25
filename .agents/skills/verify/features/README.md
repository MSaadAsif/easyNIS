# easyNIS feature map

Run these journeys against an installed checkout. Start with the features
affected by the change. The fixture represents invented discharges.

| Journey | Public workflow | Evidence |
| --- | --- | --- |
| [Open annual Parquet](open.md) | Discover files, select years, and aggregate in DuckDB | Annual row counts, selected-year checksum, and released spill directory |
| [Define a cohort](cohort.md) | Flag diagnoses and procedures and count attrition | Ordered flags, unknown timing, and sequential counts |
| [Build a survey design](survey.md) | Annualize weights, adjust costs, and apply supplied reweights | Weighted totals, standard errors, and cost provenance |
| [Review disclosure](disclosure.md) | Count contributing hospitals, then mask output cells | Original cell totals and displayed masks |
| [Create a study](study.md) | Scaffold and render a Quarto report | Generated files, render transcript, and HTML |

The journeys establish these behaviors on invented data. Use focused package
tests for optional readers, annual layouts, code lookups, label and
comorbidity helpers, and other cases outside the mapped journeys.
