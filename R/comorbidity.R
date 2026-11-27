#' Add AHRQ Elixhauser comorbidity columns (experimental)
#'
#' Reshapes the wide `I10_DX1`, `I10_DX2`, ... columns to one row per code
#' and scores them with [medicalcoder::comorbidities()]. For a lazy DuckDB
#' query, the function projects the discharge keys and diagnosis and POA
#' fields, scores up to 25,000 discharges at a time in R, then joins the
#' scores back in DuckDB. Scores are materialized when this function runs and
#' live in a temporary table on the input connection. The returned query
#' remains lazy. Use stable keys and filters, and arrange the result by key
#' if you need a specific order. For a collected input, row order is preserved.
#' All code-to-condition
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
#'   easyNIS retains the existing assumption that diagnoses in that slot were
#'   present on admission and warns once per call. NIS release files lack POA
#'   indicators, so this assumption can count hospital-acquired conditions and
#'   affect both scores. AHRQ leaves 18 of 38 measures unset when POA inputs are
#'   unavailable and requires all 38 to calculate its indices. NIS Diagnosis
#'   and Procedure Groups files provide the
#'   available HCUP-derived measures beginning in 2019. See the
#'   [AHRQ User Guide](https://hcup-us.ahrq.gov/toolssoftware/comorbidityicd10/CMR-User-Guide-v2024-1.pdf).
#' * **Principal diagnosis** is `I10_DX1`. It is passed as the primary
#'   diagnosis, and `medicalcoder` applies the AHRQ rule for it (for example, a
#'   condition is not flagged from the principal diagnosis alone where AHRQ
#'   excludes it). Codes in `I10_DX2` onward are secondary.
#'   Only positive slot suffixes without leading zeros are recognized;
#'   malformed names such as `I10_DX0` and `I10_DX01` are ignored.
#' * **ICD-10 only.** Only the `I10_DX*` columns are read. A discharge with no
#'   usable `I10_DX*` code (all blank, missing or invalid UTF-8), such as an ICD-9
#'   discharge from before October 2015, gets `NA` in every added column, and
#'   the function warns with the number of such rows. Do not treat those `NA`
#'   values as "no comorbidity".
#' * Codes are upper-cased with periods and spaces removed. Blank, missing or
#'   invalid UTF-8 codes are ignored, and an unmapped code adds no condition. A
#'   discharge with at least one usable but unmapped code gets zeros.
#' * Collected inputs are reshaped and scored in one pass. Use the DuckDB
#'   path to bound the size of the R batches for large cohorts.
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
#' design <- nis_design(nis, heart_failure, keep = c(AGE, starts_with("I10_DX"), starts_with("DXPOA")))
#' design <- nis_comorbidity(design)
#' ```
#'
#' For a `tbl_svy` the function replaces `design$variables` and leaves the
#' design (clusters, strata, weights) untouched.
#'
#' @param .data A data frame, a `tbl_svy` from [nis_design()], or a lazy DuckDB
#'   query with `I10_DX1`, `I10_DX2`, ... columns. Lazy input requires non-missing,
#'   unique discharge keys (`YEAR` and `KEY_NIS` when `YEAR` is present, otherwise
#'   `KEY_NIS` alone). Keep `YEAR` when pooling years.
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
#' # Assign stable keys to this invented fixture. NIS files supply KEY_NIS.
#' discharges <- nis_open(nis_example(years = 2019)) |>
#'   dplyr::filter(AGE >= 18) |>
#'   dplyr::mutate(KEY_NIS = dplyr::row_number()) |>
#'   dplyr::compute()
#' comorbid <- nis_comorbidity(discharges)
#' comorbid |> dplyr::select(AGE, cmrb_n, cmrb_any) |> head() |> dplyr::collect()
nis_comorbidity <- function(.data, method = "elixhauser_ahrq_icd10", prefix = "cmrb_") {
  rlang::check_installed("medicalcoder", version = "0.10.0", reason = "to compute AHRQ Elixhauser comorbidities.")
  nis_comorbidity_method(method)
  nis_comorbidity_prefix(prefix)
  design <- inherits(.data, "tbl_svy")
  records <- if (design) .data$variables else .data
  columns <- nis_comorbidity_validate_data(records)
  if (inherits(records, "tbl_sql")) {
    return(nis_comorbidity_lazy(records, method, prefix, columns))
  }

  nis_comorbidity_warn_poa(setdiff(columns$poa_fields, names(records)))
  scored <- nis_comorbidity_score(records, method, prefix, columns)
  nis_comorbidity_warn_unusable(scored$unusable)
  nis_comorbidity_check_clash(names(scored$added), names(records))
  records[names(scored$added)] <- scored$added
  if (!design) {
    return(records)
  }
  .data$variables <- records
  .data
}

nis_comorbidity_method <- function(method) {
  valid <- is.character(method) && length(method) == 1L && !is.na(method) && startsWith(method, "elixhauser_")
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
  lazy <- inherits(.data, "tbl_sql") && inherits(dbplyr::remote_con(.data), "duckdb_connection")
  if (!lazy && !is.data.frame(.data)) {
    cli::cli_abort("`.data` must be a collected data frame, a {.cls tbl_svy}, or a lazy DuckDB query.")
  }

  slot_ids <- nis_code_slots(colnames(.data), "I10_DX")
  slots <- names(slot_ids)
  if (length(slots) == 0L) {
    cli::cli_abort(c(
      "`.data` has no ICD-10 diagnosis columns (`I10_DX1`, `I10_DX2`, ...).",
      i = "When using `nis_design()`, retain them with `keep = dplyr::starts_with('I10_DX')`."
    ))
  }
  slot_number <- unname(slot_ids)
  if (!"I10_DX1" %in% slots) {
    cli::cli_abort(c(
      "`I10_DX1` is required because it identifies the principal diagnosis.",
      i = "When using `nis_design()`, retain it with `keep = dplyr::starts_with('I10_DX')`."
    ))
  }
  list(slots = slots, slot_number = slot_number, poa_fields = paste0("DXPOA", slot_number))
}

nis_comorbidity_lazy <- function(.data, method, prefix, columns) {
  existing <- colnames(.data)
  keys <- intersect(c("YEAR", "KEY_NIS"), existing)
  if (!"KEY_NIS" %in% keys) {
    cli::cli_abort("Lazy comorbidity scoring requires `KEY_NIS`. Retain `YEAR` when pooling years.")
  }
  con <- dbplyr::remote_con(.data)
  fields <- intersect(c(keys, columns$slots, columns$poa_fields), existing)
  projected <- .data |>
    dplyr::ungroup() |>
    dplyr::select(dplyr::all_of(fields)) |>
    dplyr::mutate(.nis_cmrb_row = dbplyr::sql("ROW_NUMBER() OVER ()"))
  stage <- dplyr::compute(projected, temporary = TRUE)
  stage_name <- dbplyr::remote_name(stage)
  on.exit(DBI::dbRemoveTable(con, stage_name), add = TRUE)
  rows <- nis_comorbidity_validate_keys(con, stage_name, keys)
  nis_comorbidity_warn_poa(setdiff(columns$poa_fields, fields))

  batch_name <- basename(tempfile("nis_cmrb_"))
  on.exit(DBI::dbRemoveTable(con, batch_name, fail_if_missing = FALSE), add = TRUE)
  added <- nis_comorbidity_batches(stage, rows, batch_name, method, prefix, columns, existing)

  # Recover join keys in SQL so large integer identifiers never round-trip through R.
  flags <- dplyr::tbl(con, batch_name)
  scored <- stage |>
    dplyr::select(dplyr::all_of(c(keys, ".nis_cmrb_row"))) |>
    dplyr::inner_join(flags, by = ".nis_cmrb_row") |>
    dplyr::select(dplyr::all_of(c(keys, added)))
  dplyr::left_join(.data, dplyr::compute(scored, temporary = TRUE), by = keys)
}

nis_comorbidity_validate_keys <- function(con, table, keys) {
  from <- DBI::dbQuoteIdentifier(con, table)
  fields <- DBI::dbQuoteIdentifier(con, keys)
  key_missing <- paste(fields, "IS NULL", collapse = " OR ")
  key_group <- paste(fields, collapse = ", ")
  stats <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT COALESCE(SUM(n), 0)::DOUBLE AS rows, ",
      "COALESCE(BOOL_OR(n > 1 OR missing_key), FALSE) AS invalid ",
      "FROM (SELECT COUNT(*) AS n, (",
      key_missing,
      ") AS missing_key ",
      "FROM ",
      from,
      " GROUP BY ",
      key_group,
      ") AS key_counts"
    )
  )
  if (stats$invalid) {
    cli::cli_abort("Lazy comorbidity scoring requires unique, non-missing discharge keys ({.field {keys}}).")
  }
  stats$rows
}

nis_comorbidity_batches <- function(stage, rows, table, method, prefix, columns, existing) {
  batch_size <- 25000L
  con <- dbplyr::remote_con(stage)
  fields <- intersect(c(".nis_cmrb_row", columns$slots, columns$poa_fields), colnames(stage))
  diagnoses <- dplyr::select(stage, dplyr::all_of(fields))
  row_id <- rlang::sym(".nis_cmrb_row")
  unusable <- 0
  for (first in seq(1, max(rows, 1), by = batch_size)) {
    last <- first + batch_size - 1
    batch <- diagnoses |>
      dplyr::filter(!!row_id >= !!first, !!row_id <= !!last) |>
      dplyr::collect()
    scored <- nis_comorbidity_score(batch, method, prefix, columns)
    flags <- as.data.frame(scored$added)
    flags$.nis_cmrb_row <- batch$.nis_cmrb_row
    if (first == 1) {
      nis_comorbidity_check_clash(names(scored$added), existing, lazy = TRUE)
      DBI::dbWriteTable(con, table, flags, temporary = TRUE)
    } else {
      DBI::dbAppendTable(con, table, flags)
    }
    unusable <- unusable + scored$unusable
  }
  nis_comorbidity_warn_unusable(unusable)
  names(scored$added)
}

nis_comorbidity_score <- function(.data, method, prefix, columns) {
  n <- nrow(.data)
  long <- nis_comorbidity_long(.data, columns$slots, columns$slot_number, n)
  long <- long[!is.na(long$code) & nzchar(long$code), , drop = FALSE]

  result <- medicalcoder::comorbidities(
    long,
    icd.codes = "code",
    id.vars = ".row",
    method = method,
    icdv = 10L,
    dx = 1L,
    poa.var = "poa",
    primarydx.var = "primary"
  )
  usable <- seq_len(n) %in% long$.row
  added <- nis_comorbidity_columns(result, usable, prefix)
  list(added = added, unusable = sum(!usable))
}

nis_comorbidity_check_clash <- function(added, existing, lazy = FALSE) {
  clash <- if (lazy) {
    added[nis_sql_identifier_key(added) %in% nis_sql_identifier_key(existing)]
  } else {
    intersect(added, existing)
  }
  if (length(clash) > 0L) {
    cli::cli_abort(c(
      "Comorbidity columns would replace existing column{?s} {.val {clash}}.",
      i = "Choose a different `prefix`."
    ))
  }
}

nis_comorbidity_warn_poa <- function(missing_poa) {
  if (length(missing_poa) > 0L) {
    missing_slots <- paste(sub("DXPOA", "I10_DX", missing_poa), collapse = ", ")
    cli::cli_warn(c(
      paste0(
        "No matching POA column for ",
        length(missing_poa),
        " diagnosis slots: ",
        missing_slots,
        ". Assuming present."
      ),
      i = "POA-dependent comorbidities may include conditions acquired in hospital."
    ))
  }
}

nis_comorbidity_long <- function(.data, slots, slot_number, n) {
  codes <- unlist(lapply(.data[slots], as.character), use.names = FALSE)
  codes[!validUTF8(codes)] <- NA_character_
  poa_fields <- paste0("DXPOA", slot_number)
  poa <- unlist(
    lapply(seq_along(slot_number), function(i) {
      field <- poa_fields[[i]]
      if (!field %in% names(.data)) {
        return(rep(1L, n))
      }
      value <- as.character(.data[[field]])
      value[!validUTF8(value)] <- NA_character_
      value <- toupper(value)
      unname(c(N = 0L, U = 0L, W = 1L, Y = 1L)[value])
    }),
    use.names = FALSE
  )
  data.frame(
    .row = rep(seq_len(n), times = length(slots)),
    code = toupper(gsub("[.[:space:]]", "", codes)),
    primary = as.integer(rep(slot_number == 1L, each = n)),
    poa = poa,
    stringsAsFactors = FALSE
  )
}

nis_comorbidity_warn_unusable <- function(unusable_count) {
  if (unusable_count > 0L) {
    cli::cli_warn(c(
      "{unusable_count} row{?s} {?has/have} no usable `I10_DX*` code; comorbidity columns are `NA` for {?it/them}.",
      i = "Pre-October-2015 (ICD-9) discharges have no ICD-10 diagnoses, so they cannot be scored."
    ))
  }
}

nis_comorbidity_columns <- function(result, usable, prefix) {
  result <- as.data.frame(result)
  counts <- c("num_cmrb", "mortality_index", "readmission_index")
  columns <- setdiff(names(result), ".row")
  rows <- match(seq_along(usable), result$.row)
  added <- lapply(stats::setNames(columns, columns), function(column) {
    value <- result[[column]][rows]
    value[usable & is.na(value)] <- 0L
    value[!usable] <- NA
    if (column %in% counts) as.integer(value) else value == 1L
  })
  names(added) <- paste0(
    prefix,
    ifelse(columns == "num_cmrb", "n", ifelse(columns == "cmrb_flag", "any", tolower(columns)))
  )
  added
}
