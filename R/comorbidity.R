#' Add AHRQ Elixhauser comorbidity columns (experimental)
#'
#' Reshapes the wide `I10_DX1`, `I10_DX2`, ... columns of a collected data frame
#' to one row per code, hands them to [medicalcoder::comorbidities()], and
#' joins the result back in the original row order. All code-to-condition
#' mapping and index weights come from the
#' [medicalcoder](https://CRAN.R-project.org/package=medicalcoder) package, which
#' ships the AHRQ Elixhauser Comorbidity Software Refined for ICD-10-CM tables;
#' easyNIS holds no clinical code lists. Install it with
#' `install.packages("medicalcoder")`.
#'
#' The function is experimental: the default method and the assumptions below
#' remain pending scientific approval.
#'
#' @section Assumptions:
#' * **Present on admission uses available diagnosis indicators.** Matching
#'   `DXPOAn` columns are aligned with `I10_DXn`; `Y` and `W` map to present,
#'   while `N` and `U` map to not present. Other values, including `1` and
#'   invalid UTF-8 values, are treated as unknown. `medicalcoder` applies its
#'   POA-exempt code table, based
#'   on AHRQ fiscal-year 2022 through 2026 mappings; its exemption status is not
#'   adjusted for discharge date, so exempt-code results can differ slightly
#'   from AHRQ software across fiscal years. If a matching POA column is absent,
#'   that diagnosis is assumed present to retain compatibility with older years
#'   and inputs that did not keep POA fields. A warning names the affected slots;
#'   their POA-dependent comorbidities may include conditions acquired in
#'   hospital. AHRQ's refined software requires POA to assign 18 of 38 measures
#'   and returns missing results when required POA data are unavailable
#'   ([AHRQ User Guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/CMR-User-Guide-v2024-1.pdf)).
#'   Thus, results can change for inputs that include POA fields: AHRQ's refined
#'   Elixhauser method requires POA for 18 of its 38 measures.
#' * **Principal diagnosis** is `I10_DX1`. It is passed as the primary
#'   diagnosis, and `medicalcoder` applies the AHRQ rule for it (for example, a
#'   condition is not flagged from the principal diagnosis alone where AHRQ
#'   excludes it). Codes in `I10_DX2` onward are secondary.
#' * **ICD-10 only.** Only the `I10_DX*` columns are read. A discharge with no
#'   usable `I10_DX*` code (all blank, missing or invalid UTF-8), such as an ICD-9
#'   discharge from before October 2015, gets `NA` in every added column, and
#'   the function warns with the number of such rows. Do not treat those `NA`
#'   values as "no comorbidity".
#' * Codes are upper-cased with periods and spaces removed. Blank, missing or
#'   invalid UTF-8 codes are ignored, and an unmapped code adds no condition. A
#'   discharge with at least one usable but unmapped code gets zeros.
#' * The long reshaping holds about 40 diagnosis columns by every row in memory.
#'   Use it on a cohort, not on the full national file.
#'
#' @section Differences from the Stata-derived columns:
#' NIS studies often already carry `ynel*` indicators and `elixsum`, derived in
#' Stata from an earlier Elixhauser release. They are not reproduced here and
#' should not be expected to agree: the AHRQ Refined software uses different
#' condition definitions and categories (for example, hypertension with and
#' without heart failure or renal failure, and separate liver, neurological and
#' cancer subtypes), POA-dependent flagging, and the principal-diagnosis rule
#' above. Do not mix the two sets of indicators in one model.
#'
#' @section Use with `nis_design()`:
#' `nis_design()` needs the whole hospital-year frame to build placeholder rows,
#' so do not collect and enrich the cohort before calling it. Keep the diagnosis
#' columns in the design instead, then pass the design here:
#'
#' ```r
#' design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX")))
#' design <- nis_comorbidity(design)
#' ```
#'
#' For a `tbl_svy` the function replaces `design$variables` and leaves the
#' design (clusters, strata, weights) untouched.
#'
#' @param .data A collected data frame with `I10_DX1`, `I10_DX2`, ... columns,
#'   or a `tbl_svy` from [nis_design()] that kept them. Lazy DuckDB queries are
#'   not accepted; call `dplyr::collect()` first.
#' @param method A `medicalcoder` Elixhauser method name. The default,
#'   `"elixhauser_ahrq_icd10"`, is the union of every ICD-10 code AHRQ has
#'   listed since FY2022, which suits NIS years pooled across code-set updates.
#'   Use `"elixhauser_ahrq2022"` through `"elixhauser_ahrq2026"` to pin one
#'   AHRQ release.
#' @param prefix Prefix for the added columns. Existing columns are never
#'   replaced.
#'
#' @return `.data` with one logical column per condition (`<prefix>hf`, ...),
#'   `<prefix>n` (conditions flagged), `<prefix>any`, and the integer
#'   `<prefix>mortality_index` and `<prefix>readmission_index` scores, using the
#'   names and weights from `medicalcoder`. Rows with no usable `I10_DX*` code
#'   are `NA` in all of them; see the Assumptions section.
#' @family comorbidity
#' @seealso [Comorbidity indicators](articles/comorbidity.html).
#' @export
#' @examplesIf rlang::is_installed("medicalcoder", version = "0.10.0")
#' discharges <- nis_open(nis_example(years = 2019)) |>
#'   dplyr::select(AGE, dplyr::starts_with("I10_DX")) |>
#'   dplyr::collect()
#' comorbid <- nis_comorbidity(discharges)
#' comorbid[c("AGE", "cmrb_n", "cmrb_any")] |> head()
nis_comorbidity <- function(.data, method = "elixhauser_ahrq_icd10",
                            prefix = "cmrb_") {
  rlang::check_installed("medicalcoder", version = "0.10.0",
                         reason = "to compute AHRQ Elixhauser comorbidities.")
  nis_comorbidity_options(method, prefix)
  if (inherits(.data, "tbl_svy")) {
    .data$variables <- nis_comorbidity(.data$variables, method, prefix)
    return(.data)
  }
  columns <- nis_comorbidity_validate_data(.data)
  nis_comorbidity_score(.data, method, prefix, columns$slots,
                        columns$slot_number)
}

nis_comorbidity_options <- function(method, prefix) {
  nis_comorbidity_method(method)
  nis_comorbidity_prefix(prefix)
}

nis_comorbidity_method <- function(method) {
  valid <- is.character(method) && length(method) == 1L && !is.na(method) &&
    startsWith(method, "elixhauser_")
  if (!valid) {
    cli::cli_abort("`method` must be one Elixhauser method name, such as {.val elixhauser_ahrq_icd10}.")
  }
}

nis_comorbidity_prefix <- function(prefix) {
  valid <- is.character(prefix) && length(prefix) == 1L && !is.na(prefix)
  if (!valid) {
    cli::cli_abort("`prefix` must be a single string.")
  }
}

nis_comorbidity_validate_data <- function(.data) {
  if (!is.data.frame(.data)) {
    cli::cli_abort("`.data` must be a collected data frame or a {.cls tbl_svy}; call {.fn dplyr::collect} first.")
  }

  slots <- grep("^I10_DX[0-9]+$", nis_names(.data), value = TRUE) # nolint: object_usage_linter
  if (length(slots) == 0L) {
    cli::cli_abort("`.data` has no ICD-10 diagnosis columns (`I10_DX1`, `I10_DX2`, ...).")
  }
  slot_number <- as.integer(sub("^I10_DX", "", slots))
  if (!1L %in% slot_number) {
    cli::cli_abort("`I10_DX1` is required because it identifies the principal diagnosis.")
  }
  list(slots = slots, slot_number = slot_number)
}

nis_comorbidity_score <- function(.data, method, prefix, slots, slot_number) {
  n <- nrow(.data)
  long <- nis_comorbidity_long(.data, slots, slot_number, n)
  long <- long[!is.na(long$code) & nzchar(long$code), , drop = FALSE]

  result <- medicalcoder::comorbidities(
    long, icd.codes = "code", id.vars = ".row", method = method,
    icdv = 10L, dx = 1L, poa.var = "poa", primarydx.var = "primary"
  )
  added <- nis_comorbidity_columns(result, n, long$.row, prefix)
  clash <- intersect(names(added), names(.data))
  if (length(clash) > 0L) {
    cli::cli_abort(c(
      "Comorbidity columns would replace existing column{?s} {.val {clash}}.",
      i = "Choose a different `prefix`."
    ))
  }
  .data[names(added)] <- added
  .data
}

nis_comorbidity_long <- function(.data, slots, slot_number, n) {
  codes <- unlist(lapply(.data[slots], as.character), use.names = FALSE)
  codes[!validUTF8(codes)] <- NA_character_
  poa_fields <- paste0("DXPOA", slot_number)
  missing_poa <- poa_fields[!poa_fields %in% names(.data)]
  if (length(missing_poa) > 0L) {
    missing_slots <- paste(sub("DXPOA", "I10_DX", missing_poa), collapse = ", ")
    cli::cli_warn(c(
      paste0("No matching POA column for ", length(missing_poa),
        " diagnosis slots: ", missing_slots, ". Assuming present."),
      i = "POA-dependent comorbidities may include conditions acquired in hospital."
    ))
  }
  poa <- unlist(lapply(seq_along(slot_number), function(i) {
    field <- poa_fields[[i]]
    if (!field %in% names(.data)) {
      return(rep(1L, n))
    }
    value <- as.character(.data[[field]])
    value[!validUTF8(value)] <- NA_character_
    value <- toupper(value)
    unname(c(N = 0L, U = 0L, W = 1L, Y = 1L)[value])
  }), use.names = FALSE)
  data.frame(
    .row = rep(seq_len(n), times = length(slots)),
    code = toupper(gsub("[.[:space:]]", "", codes)),
    primary = as.integer(rep(slot_number == 1L, each = n)),
    poa = poa,
    stringsAsFactors = FALSE
  )
}

nis_comorbidity_columns <- function(result, n, usable_rows, prefix) {
  result <- as.data.frame(result)
  counts <- c("num_cmrb", "mortality_index", "readmission_index")
  columns <- setdiff(names(result), ".row")
  usable <- seq_len(n) %in% usable_rows
  unusable_count <- sum(!usable)
  if (unusable_count > 0L) {
    cli::cli_warn(c(
      "{unusable_count} row{?s} {?has/have} no usable `I10_DX*` code; comorbidity columns are `NA` for {?it/them}.",
      i = "Pre-October-2015 (ICD-9) discharges have no ICD-10 diagnoses, so they cannot be scored."
    ))
  }
  added <- lapply(stats::setNames(columns, columns), function(column) {
    value <- result[[column]][match(seq_len(n), result$.row)]
    value[usable & is.na(value)] <- 0L
    value[!usable] <- NA
    if (column %in% counts) as.integer(value) else value == 1L
  })
  names(added) <- paste0(prefix, ifelse(columns == "num_cmrb", "n",
    ifelse(columns == "cmrb_flag", "any", tolower(columns))))
  added
}
