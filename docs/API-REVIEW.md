# easyNIS API review

## Analyst walkthrough

Start with [Getting started](../vignettes/getting-started.Rmd) and follow the
[analyst workflow](ANALYST-WORKFLOW.md). The walkthrough opened two years
from `nis_example()`, flagged diagnoses, added standard outcomes,
comorbidity and CCSR, selected model columns, made an adult survey domain,
fit a survey model, masked a table and annual totals, saved the domain,
and generated a report. All execution used invented data.

| Step | Where the documented path caught |
| --- | --- |
| Open and project | Open is already lazy. The analyst has to distinguish fields needed for a transformation from the smaller set to retain in `keep`. #192 provides the first projection, including the sampling fields and quarter. |
| Define and audit eligibility | The cohort article called a flag “principal” while using the any-slot matcher. Secondary slots and secondary-only cases answer different questions. Attrition needs `.design = TRUE` to match the design denominator, and reusing its eligibility requires quosure injection. |
| Enrich and label | The fixture lacked `KEY_NIS`, so lazy comorbidity needed a made-up row number and an extra materialization. `nis_label()` and `nis_cost()` required collection, while `nis_outcomes()` remained lazy. Label with `nis_design()` or after an explicit narrow collection. Costs additionally require a reference dollar year and a compatible charge field and CCR. |
| Classify | CCSR defaults to a list of categories. A principal inpatient grouping needs `position = "default"`, which produces one scalar category. The code lookup can also return a raw code vector, whose values require exact matching. |
| Build a design and restrict domains | `nis_design(cohort = ...)` preserves zero-domain hospital-years. After design construction, use `filter()` to narrow the domain. Filtering the source to the cohort first changes the sampling roster. |
| Tables and models | The row-level design supports srvyr summaries, gtsummary tables and survey models. `nis_cell_counts()` used quoted headings where table and design calls used bare selections. A count joined to an estimate must represent that estimate's actual non-missing denominator. |
| Annual trends | Use annual totals for individual years, annualization for an average annual total, and a survey model when estimating change. The coverage check and ICD-era rules are part of the estimand. |
| Suppress | Survey tables carry the counts and records used for review. Plain estimate tables need explicit discharge and hospital columns and names of the estimates to mask. Retain the numeric estimates for analysis and derive the masked display table for reporting. |
| Save and report | CCSR rebuilt the query and lost the source metadata needed by the saved-cohort writer. A reopened cohort omits `cohort` in `nis_design()`. The Quarto scaffold starts an analysis from its own input and needs the study definitions supplied there. |

## Workflow patterns in owner scripts

A read-only scan of analysis source files found recurring annual imports,
diagnosis flags, survey construction and subsetting, weighted descriptive tables
and regression, comorbidity scoring, and cost conversion. These patterns
support a short path from yearly files through derived columns to one survey
design shared by tables and models. The scan looked for code patterns in
scripts and report source. It provides no estimate of how often methods or
reporting checks occur across studies.

## Export audit

| Exports | First argument and return | API decision |
| --- | --- | --- |
| `nis_example`, `nis_open`, `nis_convert`, `nis_new_study` | `years` or `path`; directories or lazy records | Keep constructors explicit. Keep `years` numeric and use an invisible path for writers. |
| `nis_vars_design`, `nis_vars_demographics`, `nis_vars_dx`, `nis_vars_pr`, `nis_vars_hospital` | No arguments; tidyselect positions | Keep as selectors inside `select()` or `keep`. Keep strict design fields and optional annual fields distinct. |
| `nis_flag_dx`, `nis_flag_pr`, `nis_flag_dx_position`, `nis_flag_pr_timing` | `.data` (frame or query); same backend, logical flags | Keep named definitions and `system` and `position` where they describe code eligibility. Replace the standalone diagnosis-position flag helper with two calls to `nis_flag_dx()` and a logical expression. Procedure timing joins slots to days and earns its own verb. |
| `nis_add_ccsr`, `nis_ccsr_codes` | `.data` (DuckDB) to lazy records; `file` to a character vector | Keep classification and lookup available separately. Put required `categories` first in the lookup and share its release vocabulary with classification. Document the difference between exact membership and prefix matching. |
| `nis_label`, `nis_outcomes`, `nis_comorbidity`, `nis_cost`, `nis_cost_provenance` | `data` or `x` for collected access; `.data` for lazy-capable transforms | Use `.data` throughout. Outcome columns are numeric or logical in DuckDB and labels apply at the R boundary. Adjusted charges and costs have separate columns. Cost provenance earns an accessor because the report needs its method and missingness counts. |
| `nis_join_companion`, `nis_write_cohort` | `x` or `query` from `nis_open()`; lazy records or invisible path | Use `.data` throughout. Keep the join one-to-one on the Core output and retain `keep` as the writer's projection. Preserve source metadata on lazy transforms. |
| `nis_attrition`, `nis_attrition_cohort` | `.data` (frame or query) to a tibble; `flow` to a quosure | Keep accessible while the flow and design share this contract. A future design could use a common eligibility representation directly if it genuinely eliminates the need for the accessor. |
| `nis_dx_sensitivity`, `nis_prday_completeness`, `nis_audit_code_transition` | `.data` (frame or query); collected tibbles by position, slot or period | Use a discoverable `nis_audit_*` family. Distinct required inputs and output units make separate verbs easier to predict. |
| `nis_design`, `nis_reweight`, `nis_survey` | `.data`, `design`, or `query`; survey objects | Keep `design` for a design-only consumer. Use `.data` on constructors. Keep backend choice explicit while supported models and table methods differ. |
| `nis_annual_totals`, `nis_cell_counts`, `nis_suppress` | `.data` or `x`; collected summaries or the same report-table type | Use `.data`, tidyselect group keys, and keep `n` and `hospitals` as shared disclosure keys. Suppressed numeric display columns become text. |

For table verbs, take `.data` first, preserve its backend for row-preserving
transformations, and make aggregation and collection explicit in the return
contract. Use tidyselect for existing columns and data masking for logical
cohort expressions. Keep HCUP source names and snake_case derived names.
Use `name` for a single generated column and `prefix` when a family of
columns is generated. Use CLI errors that name the public argument and give
the corrective action. Existing error classes cover selected conditions such
as release mismatch and collection limits. Add classes when a caller can
recover programmatically. These choices follow dplyr's table and selection
conventions and srvyr's distinction between survey construction and estimation.
[Tidy design principles](https://design.tidyverse.org/) ·
[dplyr selection](https://dplyr.tidyverse.org/reference/select.html) ·
[srvyr reference](https://gdfe.co/srvyr/reference/index.html)

## Changes in order of user benefit

1. **Make the main path compose.** Give invented discharges a year-scoped
   key, preserve the CCSR query's source information, and teach projection,
   logical outcomes, and a design-aligned attrition denominator together.
2. **Make the next verb guessable.** Use `.data` for the first table
   argument, tidyselect for cell-count keys, and categories first in the CCSR
   lookup. Keep diagnostics together under `nis_audit_*`, and use
   `nis_flag_dx()` for position-specific flags.
3. **Extend tidyselect at the remaining column boundaries (done).** Suppression
   columns, companion fields, and diagnostic outcomes and periods resolve
   selections once and keep source names. Invented-data tests cover external
   vectors, column groups, absent fields, and lazy schemas.
4. **Keep the current cost boundary explicit.** `nis_outcomes()` derives
   Core measures, while `nis_design(dollars = ...)` and `nis_cost()` share
   the cost implementation and provenance. A lazy cost verb would need an
   explicit contract for when invalid counts and provenance are computed.
   Validate that contract before absorbing the current cost entry points.

## After #214 and #215 merge

The #214 diff adds lazy survey means, totals, grouped estimates and domain
subsetting. #215 adds supported GLMs and shares the lazy design foundation.
Both take `query` instead of `.data`. Unlike `nis_design()`, their
documented examples use `subset()` for domains. Both expose `filter()`
for the same operation and construct the design before domain restriction.
Their `weights` expression is a useful
exception to a simple column selector because it supports weight arithmetic.

- Change the public constructor's first argument to `.data` and regenerate
  its Rd page. Keep `weights` data-masked. Align the introductory examples
  around a shared lazy input and explicitly show where domain restriction
  belongs in both branches. Link the row-level design wherever a lazy
  operation such as `tbl_svysummary()` is unsupported. [#214](https://github.com/MSaadAsif/easyNIS/pull/214) · [#215](https://github.com/MSaadAsif/easyNIS/pull/215)
- Consider a common `cohort` argument only if it can reuse lazy domain
  semantics and preserve every zero-domain PSU. Verify totals, means and
  supported models against the row-level survey reference before making the
  shared call the first path in Getting started.

## Gaps from the literature

Reserved for the published NIS workflow review.
