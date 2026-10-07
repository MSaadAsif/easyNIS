# Biostatistics context review

Reviewed 2026-10-08 after Saad requested the Biostatistics folder as project context. This public note contains general package requirements. Private project names, source inventories, study-specific definitions, manuscripts, and detailed findings remain in the ignored local reference folder.

## Coverage

The full recursive inventory, including hidden and ignored files, contains 50,396 files across the five top-level branches. Git internals, dependencies, cached application state, unrelated research material, generated media, and patient-level datasets were distinguished from relevant first-party NIS/NRD context.

The text/document screening covered 3,898 source/document artifacts and identified 1,031 NIS/NRD-relevant artifacts, with 885 distinct text contents. It extracted relevant content and screened methodology; deeper semantic review concentrated on shared helpers, actual analysis workflows, codebooks, and methods passages. This does not mean every clinical formula or numerical result received independent adjudication.

The NIS source review scanned all 211 R files and recorded deeper inspection for 69. The NRD/adjacent workflow review covered 318 source/note/config files, including 210 R scripts. The parent additionally reviewed NIS presentation/configuration and dependency manifests, and screened 334 Quarto/Research artifacts with 261 distinct contents. These counts overlap and should not be summed into a unique total.

Local codebooks included official database introductions, transformed HTML data dictionaries, classification and frequency workbooks, clinical algorithm excerpts, and Stata workflow templates. Duplicate references were identified. A Word temporary lock file was not a readable document. Patient-level files were inventoried without loading records; no clinical analysis or report-rendering script was executed and no Biostatistics source was changed.

## Requirements added to the plan

| Observed recurring pattern or assumption | Package requirement |
|---|---|
| Two-stage preparation followed by tables/models/reporting. | Keep storage, analysis, and presentation contracts separate but provide one reproducible workflow. |
| Custom merged parquet and locally renamed identifiers/weights. | Require verified input profiles and provenance; names alone cannot select a historical or modern method. |
| Labels overwrite raw codes and unknowns become missing or No. | Preserve original fields; distinguish unavailable, invalid, unknown, and observed negative states. |
| Fixed diagnosis/procedure widths and concatenated code searches. | Audit annual slots; match individual codes with scope/boundaries and test R/SQL agreement. |
| Clinical lists contain ambiguous transcription/range syntax. | Validate syntax and require reviewed clinical provenance before shipping default definitions. |
| Derived comorbidity/classification fields have differing origins. | Record tool/algorithm version, principal/secondary scope, prerequisites, and redistribution terms. |
| Historical-looking fields appear in modern transformed dictionaries. | Verify the weight's actual meaning rather than inferring it from an alias. |
| Pooled identifiers are sometimes reused across years. | Validate raw IDs first, then construct and verify year-specific design keys. |
| Study-only exports precede survey design construction. | Track full-design provenance; later domain subsetting cannot restore omitted design information. |
| Private test inputs are often actual record subsets. | Public fixtures must be invented independently; private samples cannot prove national variance correctness. |
| Broad disposition codes are interpreted as specific destinations. | Use documented categories and reject unsupported narrower clinical interpretations. |
| Charges, CCR-derived costs, and inflation adjustments are mixed. | Separate quantities, validate annual CCR joins, record index/base year, and round only for display. |
| Model tables use generic exponentiation or silently omit covariates. | Report outcome/link/transformation/effect scale and requested-versus-fitted covariates explicitly. |
| Duplicated helpers, paths, and testing switches drift across outputs. | Use one analysis specification with dataset/version/mode fingerprints and standard package functions. |
| Reports use propensity, survival, spline, and multinomial methods. | Preserve interoperability; extensions outside the agreed v1 scope require separate methodological validation. |

These are static source findings and development requirements, not judgments about the correctness of any private study result.

## How this changes the first implementation

Before importing all six initial years, inventory one actual parquet conversion's schema and provenance. Define the mapping to official annual variables and determine whether the source retains the complete design population. Build two invented input profiles: source-preserving parquet and a legacy merged conversion. Include deliberately ambiguous weight aliases and incomplete provenance so the importer demonstrates useful refusal/diagnostics.

Use a single synthetic workflow to exercise table/model consistency, factor references, missingness accounting, year-specific IDs, code positions, effect scales, and disclosure through every export. Treat existing study outputs as workflow context. Independent statistical reference scripts remain necessary before marking a year supported.

The source tree also has restrictive code licensing. This review does not copy its implementation or private clinical definitions into easyNIS. New implementation remains independent under MIT, as agreed.
