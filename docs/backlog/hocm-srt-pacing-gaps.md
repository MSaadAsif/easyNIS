# Backlog: HOCM Septal Reduction Therapy and Conduction/Pacing Gaps

## Status update: 2026-10-18

The user reports that the myectomy versus alcohol septal ablation study is
completed. Its report is at
<https://msaadasif.github.io/NIS-Saad-HOCM-SRT-Pacing/>.
Treat this study as a completed reference, not a proposed new study.

The sections below are historical gap proposals. Several named helpers now
exist, so their "Existing easyNIS Coverage" descriptions are not a current
feature inventory. Check the current API before promoting a proposal to work.

See [the improvement roadmap](../IMPROVEMENT-ROADMAP.md) for current priorities.
Items 3 (curated cardiac device code sets) and 8 (AHRQ Elixhauser comorbidity
computation) in this backlog are deferred at the user's request. Do not begin
or resume either item without an explicit user instruction. The deferral does
not apply to improvement-roadmap item 3 (independent statistical validation)
or item 8 (complete teaching studies).

## Overview

During a comparative clinical study evaluating alcohol septal ablation (ASA) versus surgical septal myectomy (SM) for hypertrophic obstructive cardiomyopathy (HOCM) and subsequent permanent pacemaker (PPM) implantation across the 2017-2022 National Inpatient Sample (NIS), several analytical gaps were identified.

This document details each gap, reviews existing easyNIS coverage, and specifies proposed functions conforming to the easyNIS architecture, naming conventions, and MIT-compatible development principles. In adherence to package development guidelines, all examples and numbers herein are purely invented and illustrative, and no licensed or record-derived data are included.

---
## 1. Procedure Timing Across Paired Arrays (`I10_PR*` and `PRDAY*`)

### Proposed Function & Signature
```r
nis_flag_pr_timing(
  .data,
  index_pr,
  outcome_pr,
  name = "outcome_post_index",
  relation = c("on_or_after", "after", "before", "within_days", "same_day"),
  window = NULL,
  missing_day = c("exclude", "assume_same_day", "indeterminate"),
  system = c("icd10", "icd9")
)
```

### Purpose
In interventional and surgical comparative studies, establishing the temporal relationship between an index intervention (such as septal myectomy or alcohol septal ablation) and an outcome procedure (such as pacemaker insertion) is critical. Without temporal ordering, pre-intervention procedures cannot be separated from post-procedure complications occurring during the same hospital stay.

### Existing easyNIS Coverage
`nis_flag_pr()` flags whether a procedure code prefix appears anywhere in the procedure array (`I10_PR1`–`I10_PR25` or `PR1`–`PR25`). It has no mechanism to inspect the corresponding procedure day array (`PRDAY1`–`PRDAY25`) or evaluate temporal sequencing between paired arrays.

### Behaviour & Specification
- **Inputs:**
  - `.data`: Lazy DuckDB dataset, DuckDB table, or in-memory data frame.
  - `index_pr`: Character vector of procedure code prefixes identifying the index procedure.
  - `outcome_pr`: Character vector of procedure code prefixes identifying the outcome procedure.
  - `name`: String name for the generated logical flag (default `"outcome_post_index"`).
  - `relation`: Temporal condition to test:
    - `"on_or_after"`: Outcome procedure day >= index procedure day.
    - `"after"`: Outcome procedure day > index procedure day.
    - `"before"`: Outcome procedure day < index procedure day.
    - `"same_day"`: Outcome procedure day == index procedure day.
    - `"within_days"`: Outcome occurs within `window` days after index procedure (`0 <= PRDAY_outcome - PRDAY_index <= window`).
  - `window`: Integer specifying days for `"within_days"`.
  - `missing_day`: Policy for handling missing `PRDAY` values:
    - `"exclude"`: Returns `FALSE` if either index or outcome procedure day is missing.
    - `"assume_same_day"`: If both procedures are coded but one or both `PRDAY` values are missing, treats them as occurring on the same day (`PRDAY = 0`).
    - `"indeterminate"`: Returns `NA` when days are missing for flagged procedures.
  - `system`: Code system (`"icd10"` targeting `I10_PR*` / `PRDAY*` or `"icd9"` targeting `PR*` / `PRDAY*`).
- **Outputs:**
  - Augmented `.data` with logical column `name`.
- **Edge Cases & HCUP Conventions:**
  - **Negative `PRDAY`:** HCUP NIS codes valid procedure days as non-negative integers (>= 0, where 0 is day of admission). Negative values (e.g., `-99`, `-88`, `-66`) represent HCUP special missing codes. `nis_flag_pr_timing()` treats any negative day as missing (`NA`).
  - **Multiple Index Procedures:** If a patient receives multiple index procedure codes across different slots (e.g., myectomy in `I10_PR1` on day 1, revision in `I10_PR4` on day 3), the function binds to the earliest valid index day (`min(PRDAY_index)`).
  - **Multiple Outcome Procedures:** If multiple outcome codes occur, the condition evaluates to `TRUE` if *any* matching outcome procedure fulfills the temporal condition relative to the earliest index procedure.
  - **Absence of Index or Outcome:** If neither or only one procedure occurs, the flag is `FALSE`.

### Workaround Used by Study
The study reshaped wide procedure and timing arrays or used DuckDB expressions with explicit CASE WHEN clauses scanning across slots:
```sql
-- Plain DuckDB SQL workaround
WITH pr_long AS (
  SELECT
    KEY,
    UNNEST([I10_PR1, I10_PR2, I10_PR3, I10_PR4, I10_PR5]) AS pr_code,
    UNNEST([PRDAY1, PRDAY2, PRDAY3, PRDAY4, PRDAY5]) AS pr_day
  FROM nis_table
),
index_events AS (
  SELECT KEY, MIN(CASE WHEN pr_day >= 0 THEN pr_day END) AS min_index_day
  FROM pr_long
  WHERE pr_code LIKE '02UG%' OR pr_code LIKE '0280%'
  GROUP BY KEY
),
outcome_events AS (
  SELECT KEY, pr_day AS outcome_day
  FROM pr_long
  WHERE pr_code LIKE '0JH60%'
)
SELECT
  n.*,
  COALESCE(o.outcome_day >= i.min_index_day, FALSE) AS ppm_post_srt
FROM nis_table n
LEFT JOIN index_events i ON n.KEY = i.KEY
LEFT JOIN outcome_events o ON n.KEY = o.KEY;
```

### Minimal Invented Example
```r
library(easyNIS)
library(dplyr)

# Invented illustrative fixture
toy_data <- tibble::tibble(
  KEY     = 1:4,
  I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02UG0JZ"),
  PRDAY1  = c(0L,        2L,        3L,        -99L),
  I10_PR2 = c("0JH604Z", "0JH604Z", "0JH604Z", "0JH604Z"),
  PRDAY2  = c(1L,        1L,        3L,        2L),
  YEAR    = 2020L
)

# Flag outcomes on or after index procedure
toy_data |>
  nis_flag_pr_timing(
    index_pr = "02UG0",
    outcome_pr = "0JH60",
    name = "ppm_post_srt",
    relation = "on_or_after"
  )
# Result: Row 1 = TRUE (day 1 >= 0), Row 2 = FALSE (day 1 < 2),
#         Row 3 = TRUE (day 3 == 3), Row 4 = FALSE (negative sentinel PRDAY1 treated as missing)
```

### Suggested Tests
- `test_that("nis_flag_pr_timing detects on_or_after and same_day relationships")`: verify correct boolean flags for outcome day > index day, outcome day == index day, and outcome day < index day.
- `test_that("nis_flag_pr_timing resolves multiple index procedures to earliest day")`: verify that when index codes appear at day 3 and day 1, outcome at day 2 is flagged as post-index (`2 >= 1`).
- `test_that("nis_flag_pr_timing handles negative sentinel values and NAs")`: confirm that `-99` and `NA` are treated as missing and do not trigger false positives.
- `test_that("nis_flag_pr_timing evaluates lazily on DuckDB queries")`: ensure translation works without forcing full in-memory collection.

---
## 2. CONSORT / Attrition Table Generator

### Proposed Function & Signature
```r
nis_attrition(
  .data,
  ...,
  by_year = FALSE,
  weight_var = "DISCWT",
  collect = TRUE
)
```

### Purpose
Every observational study reporting NIS cohorts requires an attrition flowchart/table conforming to STROBE/CONSORT guidelines. Stepwise reporting of unweighted discharges, weighted national estimates, exclusion counts at each step, and percentage retained is required. Performing this lazily on DuckDB datasets or DuckDB connections avoids reading millions of national records into local memory.

### Existing easyNIS Coverage
`nis_design()` tracks valid survey design exclusions internally (`DISCWT > 0`, non-missing hospital and stratum identifiers) and attaches a summary to `attr(design, "nis_excluded")`. However, it does not support user-defined multi-step inclusion/exclusion pipelines or structured CONSORT table generation.

### Behaviour & Specification
- **Inputs:**
  - `.data`: Lazy DuckDB query, DuckDB table, or data frame.
  - `...`: Named logical expressions representing sequential exclusion criteria in execution order (e.g., `adult = AGE >= 18`, `elective = ELECTIVE == 1`, `no_prior_ppm = !prior_ppm`).
  - `by_year`: Logical; if `TRUE`, calculates step counts stratified by `YEAR`.
  - `weight_var`: String naming the survey weight column (default `"DISCWT"`).
  - `collect`: Logical; whether to return a collected tibble.
- **Outputs:**
  - A tidy tibble with columns:
    - `step`: Integer sequence (0 for initial sample, 1..k for criteria).
    - `criterion`: Description or name of applied filter.
    - `n_unweighted`: Number of unweighted discharges remaining.
    - `n_dropped_unweighted`: Unweighted discharges excluded at this step.
    - `n_weighted`: Estimated national weighted discharges remaining.
    - `n_dropped_weighted`: Weighted discharges excluded at this step.
    - `pct_retained`: Cumulative percent of unweighted discharges retained relative to Step 0.
    - If `by_year = TRUE`, includes `YEAR` column.
- **Edge Cases & Performance:**
  - **Lazy Aggregation:** Evaluates cumulative criteria using DuckDB/DuckDB compute aggregations (`SUM(CASE WHEN ... THEN 1 ELSE 0 END)` and `SUM(CASE WHEN ... THEN DISCWT ELSE 0 END)`) in a single or sequential aggregation pass rather than materializing subsets.
  - **Missing Values:** Criteria resulting in `NA` are treated as excluded, matching standard `dplyr::filter()` behavior.
  - **Zero Counts:** Safely handles empty cohorts at later steps without division-by-zero errors in `pct_retained`.

### Workaround Used by Study
The study maintained an iterative R loop executing sequential `filter()` calls and computing unweighted counts and `sum(DISCWT)`:
```r
# Plain R workaround
steps <- list(
  "All Discharges" = rlang::expr(TRUE),
  "Adult (>=18)"   = rlang::expr(AGE >= 18),
  "HOCM Diagnosis" = rlang::expr(dx_hocm == 1),
  "Elective Stay"  = rlang::expr(ELECTIVE == 1),
  "SRT Procedure"  = rlang::expr(pr_myectomy == 1 | pr_ablation == 1)
)

results <- list()
current_data <- nis_query
cum_cond <- rlang::expr(TRUE)

for (i in seq_along(steps)) {
  step_name <- names(steps)[i]
  cum_cond <- rlang::expr((!!cum_cond) & (!!steps[[i]]))
  counts <- current_data |>
    dplyr::filter(!!cum_cond) |>
    dplyr::summarise(
      n = dplyr::n(),
      n_wt = sum(DISCWT, na.rm = TRUE)
    ) |>
    dplyr::collect()
  results[[i]] <- tibble::tibble(
    step = i - 1L,
    criterion = step_name,
    n_unweighted = counts$n,
    n_weighted = counts$n_wt
  )
}
attrition_table <- dplyr::bind_rows(results)
```

### Minimal Invented Example
```r
library(easyNIS)

# Invented dataset
toy_nis <- tibble::tibble(
  AGE      = c(16, 45, 60, 72, 55),
  ELECTIVE = c(1,  1,  0,  1,  1),
  DISCWT   = c(5.0, 5.2, 4.8, 5.1, 5.0),
  YEAR     = c(2020L, 2020L, 2020L, 2020L, 2020L)
)

toy_nis |>
  nis_attrition(
    adult = AGE >= 18,
    elective = ELECTIVE == 1
  )
```

### Suggested Tests
- `test_that("nis_attrition preserves step ordering and calculates drop counts")`: verify arithmetic consistency between cumulative remaining and dropped rows.
- `test_that("nis_attrition computes weighted and unweighted counts identically on lazy DuckDB and data.frame")`: verify equivalence between lazy and in-memory execution.
- `test_that("nis_attrition handles by_year grouping correctly")`: test that stratified output maintains year-level totals.

---
## 3. Curated Cardiac Device Code Sets

Status: **DEFERRED by the user on 2026-10-18. Do not start or resume without
explicit user instruction.** The proposal below is retained for reference.

### Proposed Function & Signature
```r
nis_codes_cardiac_device(
  category = c(
    "all",
    "pacemaker_generator",
    "leadless_pacemaker",
    "transvenous_lead_only",
    "icd_crtd_generator",
    "sicd_generator",
    "temporary_pacing",
    "preexisting_device"
  )
)
```

### Purpose
ICD-10-PCS device coding involves critical clinical nuances. In electrophysiology and structural heart studies, lead-only insertion codes (`02HK3JZ` into right ventricle, `02H63JZ` into right atrium) capture both permanent transvenous leads and temporary pacing wires placed during or after catheterization. Mistaking lead-only codes for permanent pacemaker placement substantially overestimates permanent pacing complications. Furthermore, identifying pre-existing devices via ICD-10-CM Z-codes is essential to exclude patients with prior implants before estimating new pacemaker incidence.

### Existing easyNIS Coverage
easyNIS explicitly ships no clinical code lists (`AGENTS.md` and `README.md` note: "easyNIS ships no code lists"). Analysts must construct large code vectors by hand, risking systematic classification errors across publications.

### Behaviour & Specification
- **Inputs:**
  - `category`: String selection for the required device category, or `"all"` for a named list of all categories.
- **Outputs:**
  - Character vector of standardized uppercase alphanumeric ICD-10-PCS or ICD-10-CM codes.
- **Curated Code Categories:**
  Device character (6th) in table `0JH` (chest `0JH6`, abdomen `0JH8`; approach 0 open / 3 percutaneous):
  4 = pacemaker single chamber, 5 = single chamber rate responsive, 6 = dual chamber,
  7 = CRT pacemaker (CRT-P), 8 = defibrillator generator, 9 = CRT defibrillator (CRT-D),
  P = cardiac rhythm related device, F = subcutaneous defibrillator lead.
  1. `pacemaker_generator` (ICD-10-PCS): `0JH6[03][4567P]Z` and `0JH8[03][4567P]Z`
     (e.g. `0JH604Z`, `0JH606Z`, `0JH607Z`, `0JH60PZ`, `0JH834Z`). Note that CRT-P (`7`) is a pacemaker.
  2. `leadless_pacemaker` (ICD-10-PCS): intracardiac pacemaker, device character `N`
     (`02HK3NZ` right ventricle; atrial leadless codes added in later code years — check the code year).
  3. `transvenous_lead_only` (ICD-10-PCS): pacemaker lead (`J`) or defibrillator lead (`K`/`M`, verify per code year)
     into right atrium `02H6`, right ventricle `02HK`, coronary vein `02H4` without a generator code — captures
     lead revisions and temporary transvenous/epicardial wires (e.g. `02HK3JZ`, `02H63JZ`).
  4. `icd_crtd_generator` (ICD-10-PCS): `0JH6[03][89]Z`, `0JH8[03][89]Z` (e.g. `0JH608Z`, `0JH609Z`).
  5. `sicd` (ICD-10-PCS): defibrillator generator `0JH608Z`/`0JH638Z` together with subcutaneous
     defibrillator lead `0JH60FZ`/`0JH63FZ`.
  6. `temporary_pacing` (ICD-10-PCS): `5A1213Z` (cardiac pacing, intermittent) and `5A1223Z`
     (cardiac pacing, continuous). Do not confuse with `5A1221Z` (cardiac output, continuous — cardiopulmonary bypass).
  Every list must be validated against the CMS ICD-10-PCS code tables for each fiscal year before release.
  7. `preexisting_device` (ICD-10-CM): Secondary diagnosis codes indicating presence or management of an existing device:
     - `Z950` (Presence of cardiac pacemaker).
     - `Z95810` (Presence of automatic implantable cardioverter-defibrillator).
     - `Z4501` (Encounter for adjustment and management of cardiac pacemaker).
     - `Z4502` (Encounter for adjustment and management of automatic implantable cardioverter-defibrillator).
     - `T821` (Mechanical complication of cardiac electronic device).

### Workaround Used by Study
The study maintained an isolated R script containing manually defined code vectors:
```r
# Plain R workaround
ppm_generators <- c("0JH604Z", "0JH605Z", "0JH606Z", "0JH60PZ")
leadless_ppm   <- c("02HK3NZ")
lead_only_wire <- c("02HK3JZ", "02H63JZ")
prior_device   <- c("Z950", "Z95810", "Z4501", "Z4502")

nis_flagged <- nis_data |>
  nis_flag_pr(ppm_gen = ppm_generators, leadless = leadless_ppm, lead_only = lead_only_wire) |>
  nis_flag_dx(prior_dev = prior_device) |>
  dplyr::mutate(
    # Distinct permanent pacemaker vs temporary wire
    new_perm_ppm = (ppm_gen | leadless) & !prior_dev,
    isolated_lead_wire = lead_only & !ppm_gen & !leadless
  )
```

### Minimal Invented Example
```r
library(easyNIS)

codes <- nis_codes_cardiac_device()

# Inspect permanent pacemaker generator codes vs lead-only codes
head(codes$pacemaker_generator)
head(codes$transvenous_lead_only)

# Use directly with existing easyNIS functions
toy_data <- tibble::tibble(
  I10_PR1 = c("0JH604Z", "02HK3JZ", "02HK3NZ"),
  YEAR    = 2020L
)

toy_data |>
  nis_flag_pr(
    perm_ppm  = codes$pacemaker_generator,
    leadless  = codes$leadless_pacemaker,
    lead_only = codes$transvenous_lead_only
  )
```

### Suggested Tests
- `test_that("nis_codes_cardiac_device returns expected categories")`: check that all 7 defined categories exist in list output.
- `test_that("device categories are mutually distinct where clinically required")`: verify that `pacemaker_generator` and `transvenous_lead_only` share no overlapping codes.
- `test_that("code vectors conform to alphanumeric without punctuation")`: ensure no dots or spaces exist in code strings.

---
## 4. DuckDB-native Parquet scanning (implemented)

`nis_open(path, years = NULL)` now reads Parquet through DuckDB's native
`read_parquet()` table function. It unions annual schemas by column name,
supports `YEAR=YYYY` Hive-partitioned directories, normalizes field names, and
returns a lazy dbplyr query. DuckDB connections are released with the lazy
query lifecycle. `nis_example()` writes its invented fixtures with DuckDB's
Parquet `COPY` writer. `duckdb`, `dbplyr`, and `DBI` are required dependencies.

The former `engine` argument and Arrow bridge were removed. The reader relies on
DuckDB's UTF-8 string handling; source Parquet containing malformed UTF-8 may
need correction before it can be scanned. SQL inputs are quoted through DBI,
and tests cover lazy results, schema union, Hive years, path quoting, and
Parquet round trips.

---
## 5. Code-Transition and Coding-Shift Audit Helper

### Proposed Function & Signature
```r
nis_audit_code_transition(
  .data,
  codes,
  cohort = NULL,
  by = "YEAR",
  system = c("icd10", "icd9")
)
```

### Purpose
In longitudinal NIS analyses spanning multiple years (e.g., 2017–2022), changes in ICD-10-PCS coding guidelines or introducing new specific technology codes create artificial coding shifts. For example, the emergence of specific codes for transcatheter intracardiac pacemakers or changes in coding clinic recommendations for septal reduction can cause sharp multi-year discontinuities. An audit helper tabulates code-specific frequencies over time within a target cohort to identify code substitutions and guideline artifacts before fixing study definitions.

### Existing easyNIS Coverage
`nis_flag_pr()` and `nis_flag_dx()` test whether *any* code in a prefix list is present. They collapse all candidate codes into a single boolean indicator, masking whether code A is replacing code B over time.

### Behaviour & Specification
- **Inputs:**
  - `.data`: Lazy DuckDB query, DuckDB connection, or collected data frame.
  - `codes`: Named character vector or list of candidate ICD-10-PCS or CM codes (e.g., `c(surgical = "02UG0JZ", transcatheter = "02803ZZ")`).
  - `cohort`: Optional unquoted logical expression filtering to the target cohort before auditing.
  - `by`: Grouping column for the timeline (default `"YEAR"`).
  - `system`: `"icd10"` or `"icd9"`.
- **Outputs:**
  - Tidy summary tibble with columns:
    - Grouping column (e.g., `YEAR`).
    - `code_group`: Name or code prefix.
    - `n_unweighted`: Unweighted count of discharges containing the code.
    - `n_weighted`: Weighted count of discharges.
    - `pct_within_year`: Percent of cohort discharges in that year carrying the code.
    - `year_over_year_pct_change`: Relative percent change in frequency compared to the preceding year.
- **Edge Cases:**
  - Years with 0 occurrences of a code are preserved with `n = 0` and `pct = 0.0`.
  - Discharges with multiple matching codes within the same code group are counted once per discharge.

### Workaround Used by Study
The study unnested procedure slots in DuckDB and aggregated frequencies by year:
```sql
-- Plain DuckDB SQL workaround
WITH unnested AS (
  SELECT
    YEAR,
    DISCWT,
    UNNEST([I10_PR1, I10_PR2, I10_PR3, I10_PR4]) AS pr
  FROM cohort_table
)
SELECT
  YEAR,
  pr,
  COUNT(*) AS n_unweighted,
  SUM(DISCWT) AS n_weighted,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY YEAR), 2) AS pct_in_year
FROM unnested
WHERE pr IN ('02UG0JZ', '02803ZZ', '02HK3NZ')
GROUP BY YEAR, pr
ORDER BY pr, YEAR;
```

### Minimal Invented Example
```r
library(easyNIS)

toy_data <- tibble::tibble(
  YEAR    = c(2018L, 2018L, 2019L, 2019L, 2020L, 2020L),
  I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02803ZZ", "02803ZZ", "02803ZZ"),
  DISCWT  = c(5, 5, 5, 5, 5, 5)
)

toy_data |>
  nis_audit_code_transition(
    codes = c(myectomy = "02UG0JZ", ablation = "02803ZZ"),
    by = "YEAR"
  )
```

### Suggested Tests
- `test_that("nis_audit_code_transition returns 0 counts for unobserved codes in a given year")`: verify complete Cartesian grid of year x code.
- `test_that("nis_audit_code_transition computes weighted and unweighted frequencies accurately")`: test manual sum against returned columns.
- `test_that("nis_audit_code_transition respects cohort filtering expression")`: confirm filtering criteria exclude non-cohort records before counting.

---
## 6. Principal-vs-Any Diagnosis Cohort Sensitivity Helper

### Proposed Function & Signature
```r
nis_dx_sensitivity(
  .data,
  code,
  name = "dx_condition",
  system = c("icd10", "icd9")
)
```

### Purpose
In administrative database research, defining a cohort by principal diagnosis (`I10_DX1`) versus secondary or any diagnosis (`I10_DX1..25`) has major clinical implications. In HOCM, principal diagnosis identifies hospitalizations primarily driven by symptomatic obstructive cardiomyopathy, whereas secondary diagnosis captures incidental HOCM in patients admitted for trauma, pneumonia, or unrelated surgery. Peer reviewers routinely demand sensitivity analyses assessing diagnostic concordance and outcome stability across principal versus secondary classifications.

### Existing easyNIS Coverage
`nis_flag_dx()` provides a `position` argument (`position = c("any", "principal", "secondary")`).
- **Does this suffice?** Partially. `nis_flag_dx()` enables the creation of distinct flags. However, it does not provide an automated mechanism to cross-tabulate concordance (Cohen's kappa, positive agreement, sensitivity/specificity analogs) or summarize baseline differences between principal-only and secondary-only subgroups. Analysts currently must manually construct multiple designs, duplicate summary tables, and write ad-hoc comparison code.

### Behaviour & Specification
- **Inputs:**
  - `.data`: Lazy DuckDB query, DuckDB table, or data frame.
  - `code`: Diagnosis code prefix (e.g., `"I421"` for HOCM).
  - `name`: Base name for generated flags.
  - `system`: `"icd10"` or `"icd9"`.
- **Outputs:**
  - When used as a flagging step: Adds `<name>_principal`, `<name>_secondary`, and `<name>_any` logical columns.
  - When paired with `summary = TRUE` or a dedicated summary method: Returns a cross-tabulation table reporting:
    - Unweighted and weighted counts of Principal, Secondary-only, and Total.
    - Percent of all diagnoses where the condition was the primary reason for admission.
    - In-hospital mortality rate and elective admission rate compared between Principal vs Secondary-only presentations.
- **Edge Cases:**
  - Discharges with no diagnosis codes are assigned `FALSE` across all three flags.
  - By definition, `principal` is a strict subset of `any`.

### Workaround Used by Study
The study executed two separate flagging passes and constructed a contingency table:
```r
# Plain R workaround
study_data <- nis_data |>
  nis_flag_dx(hocm_principal = "I421", position = "principal") |>
  nis_flag_dx(hocm_any = "I421", position = "any") |>
  dplyr::mutate(hocm_secondary_only = hocm_any & !hocm_principal)

# Calculate concordance and baseline divergence
comparison <- study_data |>
  dplyr::group_by(hocm_principal, hocm_secondary_only) |>
  dplyr::summarise(
    n = dplyr::n(),
    n_weighted = sum(DISCWT, na.rm = TRUE),
    mortality = mean(DIED == 1, na.rm = TRUE),
    elective_pct = mean(ELECTIVE == 1, na.rm = TRUE),
    .groups = "drop"
  )
```

### Minimal Invented Example
```r
library(easyNIS)

toy_data <- tibble::tibble(
  I10_DX1 = c("I421", "I210", "I421"),
  I10_DX2 = c("I509", "I421", "E119"),
  DISCWT  = c(5.0,    5.0,    5.0)
)

toy_data |>
  nis_dx_sensitivity(code = "I421", name = "hocm")
```

### Suggested Tests
- `test_that("nis_dx_sensitivity verifies principal is a strict subset of any")`: verify that `<name>_principal == TRUE` implies `<name>_any == TRUE`.
- `test_that("nis_dx_sensitivity accurately separates secondary-only cases")`: verify mutually exclusive categories between principal and secondary-only.

---
## 7. Small-Cell Suppression for gtsummary and Weighted Counts

### Proposed Function & Signature
```r
nis_suppress(
  x,
  threshold = 10,
  weighted_cols = NULL,
  secondary = TRUE
)
```

### Purpose
The HCUP Data Use Agreement (DUA) strictly prohibits reporting any cell (tabular or graphic) representing 1 to 10 unweighted discharges. Furthermore, reporting derived weighted estimates when the underlying unweighted cell is <= 10 violates DUA requirements if the unweighted count can be deduced. Additionally, in stratified tables with row or column totals, secondary (complementary) masking is required to prevent exact algebraic back-calculation (e.g., subtracting known unmasked cells from the total).

### Existing easyNIS Coverage & Gaps
`nis_suppress()` exists in `R/suppress.R`.
- **Current behaviour:** It takes a `gtsummary::tbl_svysummary()` object, looks up `n_unweighted` from `cards$tbl_svysummary`, and replaces displayed values with `<= 10`. If a by-group cell is masked, it marks the overall column (`stat_0`) as `"Masked"`.
- **Gaps:**
  1. **Strict Class Restriction:** It only accepts `gtsummary::tbl_svysummary` objects. It immediately errors on standard `data.frame` or `tibble` outputs from `dplyr::summarise()`, `srvyr::survey_total()`, or custom reporting scripts.
  2. **Derived Weighted Counts:** When displaying weighted population totals in custom tables (e.g., total estimated procedures), easyNIS provides no helper to mask the weighted estimate column based on an unweighted count column.
  3. **Secondary / Complementary Masking:** While `nis_suppress()` masks `stat_0` in `gtsummary`, it does not perform complementary masking across multi-level categorical by-variables. If group A has <= 10 and group B has 100 with a total of 105, masking group A and the total still allows exact derivation of group A (105 - 100 = 5). Complementary suppression must mask the second smallest group.

### Behaviour & Specification
- **Inputs:**
  - `x`: Either a `gtsummary::tbl_svysummary` object OR a `data.frame` / `tibble`.
  - `threshold`: Integer cutoff (default 10).
  - `weighted_cols`: Character vector of column names in a `data.frame` to mask when the corresponding unweighted count column is <= threshold.
  - `secondary`: Logical; if `TRUE`, applies complementary suppression to the second smallest cell in a row/stratification group when primary suppression occurs.
- **Outputs:**
  - Same class as input `x` with masked cells replaced by `"<= 10"` (or `NA` for numeric matrices) and complementary masked cells marked `"Masked"`.
- **Edge Cases:**
  - Cells with count 0 are not suppressed (0 is permitted by HCUP guidelines as it indicates absence of events).
  - Handles missing / non-finite values gracefully without crashing.

### Workaround Used by Study
The study applied custom post-processing to summary tables before export:
```r
# Plain R workaround for data frames
suppress_counts <- function(df, n_col, wt_col, threshold = 10) {
  df |>
    dplyr::mutate(
      masked = .data[[n_col]] > 0 & .data[[n_col]] <= threshold,
      !!wt_col := dplyr::if_else(masked, NA_real_, .data[[wt_col]]),
      !!n_col := dplyr::if_else(masked, NA_real_, .data[[n_col]])
    )
}
```

### Minimal Invented Example
```r
library(easyNIS)

# Invented aggregate summary table
summary_df <- tibble::tibble(
  group        = c("Ablation", "Myectomy"),
  unweighted_n = c(4L,         45L),
  weighted_n   = c(20.5,       230.1)
)

# Suppress both unweighted and derived weighted counts
summary_df |>
  nis_suppress(
    threshold = 10,
    weighted_cols = "weighted_n"
  )
```

### Suggested Tests
- `test_that("nis_suppress accepts data.frame inputs and masks paired weighted columns")`: verify that unweighted count of 4 suppresses both unweighted and weighted columns.
- `test_that("nis_suppress leaves 0 counts unmasked")`: confirm that `n = 0` remains visible.
- `test_that("nis_suppress performs secondary suppression on binary strata")`: confirm that masking one stratum prompts masking of the complementary stratum to prevent subtraction deduction.

---
## 8. Elixhauser Comorbidity Computation for ICD-10 NIS Records

Status: **DEFERRED by the user on 2026-10-18. Do not start or resume without
explicit user instruction.** This deferral concerns the proposed AHRQ
comorbidity extension below, not existing `nis_comorbidity()` functionality.

### Proposed Function & Signature
```r
nis_comorbidity_ahrq(
  .data,
  version = "v2023",
  engine = c("duckdb", "r"),
  prefix = "cmrb_"
)
```

### Purpose
Risk adjustment using the Healthcare Cost and Utilization Project (HCUP) AHRQ Elixhauser Comorbidity Software Refined for ICD-10-CM is standard in NIS surgical and procedural research. It maps 38 comorbidity categories and generates calibrated mortality and readmission index scores.

### Existing easyNIS Coverage & Gaps
`nis_comorbidity()` exists in `R/comorbidity.R`.
- **Current behaviour:** It reshapes wide `I10_DX1`–`I10_DXk` columns of a collected data frame to long format and calls `medicalcoder::comorbidities()`.
- **Gaps:**
  1. **Licensing Friction:** `medicalcoder` is licensed under GPL-3, creating license tension with easyNIS's permissive MIT license and the AGENTS.md mandate ("Use invented public fixtures and independent MIT code").
  2. **Memory Blowup & Lack of Laziness:** It requires `dplyr::collect()` first. Reshaping 40 diagnosis columns for hundreds of thousands of discharges creates an intermediate object of tens of millions of rows in local RAM, causing out-of-memory crashes on typical workstations. It cannot evaluate lazily in DuckDB or R.
  3. **Heavy Dependency:** If `medicalcoder` is not installed or CRAN binary compilation fails in locked down research environments, comorbidity scoring is completely unavailable.

### Behaviour & Specification
- **Independent MIT Implementation:**
  - Derive comorbidity category mapping directly from the public-domain AHRQ Elixhauser Comorbidity Software Refined v2022–v2025 crosswalk tables published by AHRQ.
  - Implement scoring as an in-package join table or compiled SQL expression table.
- **Inputs:**
  - `.data`: Lazy DuckDB query, DuckDB connection, or data frame.
  - `version`: AHRQ software release version (`"v2022"`, `"v2023"`, `"v2024"`, `"v2025"`).
  - `engine`: Compute backend (`"duckdb"` or `"r"`).
  - `prefix`: Column prefix (default `"cmrb_"`).
- **Outputs:**
  - Augmented `.data` with 38 logical comorbidity indicators (e.g., `<prefix>hf`, `<prefix>dm_cx`), summary condition count `<prefix>n`, `<prefix>any`, and numeric risk index weights `<prefix>mortality_index` and `<prefix>readmission_index`.
- **Edge Cases & HCUP Rules:**
  - **Principal Diagnosis Rule:** Conditions where AHRQ excludes the principal diagnosis (e.g., uncomplicated hypertension coded as primary reason for admission) are correctly suppressed.
  - **Absence of POA:** Since public NIS lacks Present on Admission (POA) flags, every diagnosis is evaluated as present on admission, consistent with published HCUP conventions.

### Workaround Used by Study
The study either executed a memory-intensive chunked loop through `medicalcoder::comorbidities()` or joined against a DuckDB reference table populated from public AHRQ CSV files:
```sql
-- Plain DuckDB SQL workaround
WITH dx_long AS (
  SELECT
    KEY,
    1 AS is_primary,
    I10_DX1 AS dx
  FROM cohort
  UNION ALL
  SELECT
    KEY,
    0 AS is_primary,
    UNNEST([I10_DX2, I10_DX3, I10_DX4, I10_DX5]) AS dx
  FROM cohort
),
mapped AS (
  SELECT
    d.KEY,
    m.comorbidity_category
  FROM dx_long d
  JOIN ahrq_elixhauser_ref m ON d.dx = m.icd10_code
  WHERE NOT (d.is_primary = 1 AND m.exclude_primary = 1)
)
SELECT
  KEY,
  MAX(CASE WHEN comorbidity_category = 'HF' THEN 1 ELSE 0 END) AS cmrb_hf,
  MAX(CASE WHEN comorbidity_category = 'DM_CX' THEN 1 ELSE 0 END) AS cmrb_dm_cx
FROM mapped
GROUP BY KEY;
```

### Minimal Invented Example
```r
library(easyNIS)

# Invented toy cohort with ICD-10 diagnoses
toy_cohort <- tibble::tibble(
  KEY     = 1:2,
  I10_DX1 = c("I421", "I5020"), # HOCM vs Heart Failure primary
  I10_DX2 = c("E119", "I421"),  # Type 2 diabetes vs HOCM secondary
  DISCWT  = c(5.0,    5.0)
)

# Score comorbidities directly
toy_cohort |>
  nis_comorbidity_ahrq(prefix = "cmrb_")
```

### Suggested Tests
- `test_that("nis_comorbidity_ahrq scores diabetes and heart failure correctly")`: test against known ICD-10 codes without requiring external GPL packages.
- `test_that("nis_comorbidity_ahrq applies principal diagnosis exclusion rule")`: confirm that when a condition is coded only in `I10_DX1` and AHRQ excludes primary presentations, the indicator remains `FALSE`.
- `test_that("nis_comorbidity_ahrq evaluates lazily in DuckDB")`: verify that comorbidity scoring can be prepended to survey design without intermediate R memory collection.

---

## Summary of Proposed Extensions

| # | Gap Area | Proposed Function | Target Pipeline Stage | Primary Benefit |
|---|---|---|---|---|
| 1 | Procedure Timing | `nis_flag_pr_timing()` | Cohort Definition & Outcome Flagging | Validates post-procedure complications using `PRDAY*` arrays |
| 2 | Attrition Flowchart | `nis_attrition()` | Study Reporting & Setup | Generates STROBE/CONSORT tables lazily without memory blowup |
| 3 | Cardiac Devices (**DEFERRED**) | `nis_codes_cardiac_device()` | Code Selection & Phenotyping | Disambiguates permanent pacemakers from temporary pacing wires |
| 4 | Parquet Scanning (**IMPLEMENTED**) | `nis_open()` | File Ingestion & Querying | Native DuckDB Parquet scans with lazy dplyr queries |
| 5 | Code Transitions | `nis_audit_code_transition()` | Longitudinal Validation | Detects multi-year coding shifts and guideline artifacts |
| 6 | Position Sensitivity | `nis_dx_sensitivity()` | Sensitivity Analysis | Standardizes Principal vs Any diagnosis concordance reporting |
| 7 | Small-Cell Masking | `nis_suppress()` (extended) | Disclosure & DUA Compliance | Supports plain data frames, weighted totals, and complementary masking |
| 8 | Comorbidity Scoring (**DEFERRED**) | `nis_comorbidity_ahrq()` | Risk Adjustment | Independent MIT implementation supporting lazy in-database execution |
