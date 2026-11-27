#' Add comorbidity indicators and scores (experimental)
#'
#' DuckDB unpivots diagnosis slots, maps codes to conditions, and applies
#' present-on-admission and hierarchy rules within each discharge. Lazy queries
#' stay in DuckDB. The function runs a key and diagnosis-availability check
#' before returning the score query. Collected data frames keep their row order.
#'
#' @section Coding and present on admission:
#' * Use ICD-10-CM `I10_DX*` or ICD-9-CM `DX*` slots as supported by the
#'   method. The first slot identifies the principal diagnosis and is excluded
#'   from flags. When supplied, `YEAR`, `DQTR` and `DXVER` identify eligible
#'   diagnosis slots. Deyo also reads eligible ICD-9-CM `PR*` slots when
#'   available and mapped. Keep ICD-9 codes as strings to retain leading zeros.
#' * Codes use uppercase with periods and ASCII whitespace removed. Rows with
#'   usable codes that map to no conditions receive zeros. Rows without usable
#'   codes for the method receive missing scores and trigger a warning.
#' * Refined AHRQ and Charlson align `DXPOAn` to the diagnosis suffix `n`.
#'   `Y` and `W` mean present, `N` and `U` mean absent, and other values
#'   including `1` mean unknown. Refined AHRQ also uses code-specific
#'   exemptions. For methods sourced from medicalcoder, repeated diagnoses
#'   that map to the same category and exemption state follow its data.frame
#'   precedence (unknown, then present, then absent).
#' * If a matching POA field is absent, easyNIS warns and assumes those
#'   diagnoses were present. NIS releases generally lack POA indicators, so
#'   this assumption can count conditions acquired during a hospital stay.
#'   AHRQ's software leaves 18 of 38 measures unset when POA is unavailable.
#' * `elixhauser_ahrq2027` selects its exemption list using the discharge
#'   fiscal year (calendar `YEAR` plus one for `DQTR == 4`). When the
#'   quarter is missing it uses the calendar year. When the year is missing
#'   or after the release, it uses the latest fiscal year in the release.
#'   The other refined methods use medicalcoder's fixed exemptions.
#'
#' @section Use with `nis_design()`:
#' Retain diagnosis slots and available POA fields using `keep`, then pass
#' the design to `nis_comorbidity()`. For a `tbl_svy`, only the design's
#' variables are enriched. The clusters, strata and weights are preserved.
#'
#' @param .data A data frame, a `tbl_svy` from [nis_design()], or a lazy DuckDB
#'   query. Lazy input requires non-missing, unique `KEY_NIS`, or unique pairs
#'   of `YEAR` and `KEY_NIS` when `YEAR` is present. Keep `YEAR` when
#'   pooling years.
#' @param method Comorbidity definition. The default `"elixhauser_ahrq_icd10"`
#'   uses the medicalcoder ICD-10-CM union. `"elixhauser_ahrq2022"` through
#'   `"elixhauser_ahrq2027"` select a specific release. Use
#'   `"charlson_quan2005"` for Quan coding with original Charlson weights,
#'   `"charlson_quan2011"` for the same coding with Quan 2011 weights, and
#'   `"charlson_deyo1992"` for Deyo ICD-9-CM coding with original weights.
#'   `"elixhauser_quan2005"` uses Quan ICD-9-CM or ICD-10 coding and legacy
#'   AHRQ weights. `"elixhauser_ahrq_web"` and `"elixhauser_elixhauser1998"`
#'   replicate medicalcoder's legacy ICD-9 code-based algorithms. All methods
#'   except FY2027 require the optional medicalcoder package.
#' @param prefix Prefix for the added columns. Choose a prefix that does not
#'   collide with an existing name.
#'
#' @return `.data` with logical condition flags and `<prefix>any`, the
#'   integer count `<prefix>n`, and either `<prefix>mortality_index` and
#'   `<prefix>readmission_index` (Elixhauser) or `<prefix>cci` (Charlson).
#'   Charlson scores are based on diagnoses and any mapped procedures without
#'   an age adjustment.
#' @family comorbidity
#' @seealso [Comorbidity indicators](articles/comorbidity.html).
#' @export
#' @examples
#' discharges <- data.frame(I10_DX1 = "Z0000", I10_DX2 = "I509", DXPOA1 = "Y", DXPOA2 = "Y")
#' nis_comorbidity(discharges, method = "elixhauser_ahrq2027")$cmrb_mortality_index
nis_comorbidity <- function(.data, method = "elixhauser_ahrq_icd10", prefix = "cmrb_") {
  rlang::check_installed("medicalcoder", version = "0.10.0", reason = "to look up comorbidity mappings.")
  spec <- nis_comorbidity_spec(method)
  if (!is.character(prefix) || length(prefix) != 1L || is.na(prefix)) {
    cli::cli_abort("`prefix` must be a single string.")
  }
  design <- inherits(.data, "tbl_svy")
  records <- if (design) .data$variables else .data
  slots <- nis_comorbidity_slots(records, spec)
  added <- paste0(prefix, c(tolower(spec$conditions), "n", "any", names(spec$weights)))
  lazy <- inherits(records, "tbl_sql")
  nis_comorbidity_check_clash(added, colnames(records), lazy)
  if (lazy) {
    return(nis_comorbidity_lazy(records, spec, slots, added))
  }

  records[added] <- nis_comorbidity_frame(records, spec, slots, added)
  if (!design) {
    return(records)
  }
  .data$variables <- records
  .data
}

nis_comorbidity_slots <- function(records, spec) {
  lazy <- inherits(records, "tbl_sql") && inherits(dbplyr::remote_con(records), "duckdb_connection")
  if (!lazy && !is.data.frame(records)) {
    cli::cli_abort("`.data` must be a collected data frame, a {.cls tbl_svy}, or a lazy DuckDB query.")
  }

  fields <- colnames(records)
  slots <- lapply(spec$systems, function(system) {
    stem <- nis_code_stem("DX", paste0("icd", system))
    ids <- nis_code_slots(fields, stem)
    if (!length(ids)) {
      return(NULL)
    }
    if (!"1" %in% ids) {
      cli::cli_abort(c(
        "{.field {paste0(stem, '1')}} is required because it identifies the principal diagnosis.",
        i = "When using `nis_design()`, retain the principal diagnosis with `keep`."
      ))
    }
    data.frame(
      name = names(ids),
      kind = "DX",
      version = system,
      principal = ids == "1",
      poa = if (spec$poa) paste0("DXPOA", ids) else NA_character_
    )
  })
  slots <- do.call(rbind, slots)
  if (is.null(slots)) {
    era <- paste(paste0("ICD-", spec$systems), collapse = " or ")
    cli::cli_abort(c(
      "`.data` has no {era} diagnosis columns.",
      i = "When using `nis_design()`, retain them with `keep`."
    ))
  }
  if (isTRUE(spec$procedures) && 9L %in% slots$version) {
    pr <- names(nis_code_slots(fields, "PR"))
    if (length(pr)) {
      slots <- rbind(slots, data.frame(name = pr, kind = "PR", version = 9L, principal = FALSE, poa = NA_character_))
    }
  }
  slots
}

nis_comorbidity_lazy <- function(records, spec, slots, added) {
  keys <- intersect(c("YEAR", "KEY_NIS"), colnames(records))
  if (!"KEY_NIS" %in% keys) {
    cli::cli_abort("Lazy comorbidity scoring requires `KEY_NIS`. Retain `YEAR` when pooling years.")
  }
  con <- dbplyr::remote_con(records)
  inputs <- nis_cmrb_inputs(records, slots, keys, spec$fiscal_exemptions)
  quoted_keys <- DBI::dbQuoteIdentifier(con, keys)
  unusable <- nis_cmrb_validate_keys(con, inputs, quoted_keys, keys)
  nis_comorbidity_warn_poa(slots, colnames(records))
  nis_comorbidity_warn_unusable(unusable, spec$systems)
  sql <- nis_cmrb_score_sql(con, inputs, quoted_keys, spec, added)
  scores <- dplyr::tbl(con, dbplyr::sql(sql), vars = c(keys, added))
  dplyr::left_join(records, scores, by = keys)
}

nis_comorbidity_frame <- function(records, spec, slots, added) {
  db <- nis_duckdb_open_data()
  on.exit(db$release())
  con <- db$con
  nis_comorbidity_warn_poa(slots, names(records))
  extra <- intersect(c("YEAR", "DQTR", "DXVER", "PRVER"), names(records))
  fields <- intersect(c(slots$name, slots$poa), names(records))
  input <- as.data.frame(records[unique(c(fields, extra))])
  input[fields] <- lapply(input[fields], function(value) {
    value <- as.character(value)
    value[!validUTF8(value)] <- NA_character_
    value
  })
  if (is.factor(input$DQTR)) {
    # Design labels store Q1 through Q4, while the scoring SQL uses codes.
    input$DQTR <- match(sub("^Q", "", as.character(input$DQTR)), as.character(1:4))
  }
  input$.nis_cmrb_row <- seq_len(nrow(records))
  duckdb::duckdb_register(con, "discharges", input)

  key <- ".nis_cmrb_row"
  inputs <- nis_cmrb_inputs(dplyr::tbl(con, "discharges"), slots, key, spec$fiscal_exemptions)
  sql <- nis_cmrb_score_sql(con, inputs, DBI::dbQuoteIdentifier(con, key), spec, added)
  scores <- DBI::dbGetQuery(con, sql)
  rows <- match(input$.nis_cmrb_row, scores$.nis_cmrb_row)
  nis_comorbidity_warn_unusable(sum(is.na(rows)), spec$systems)
  as.list(scores[rows, added, drop = FALSE])
}

nis_comorbidity_check_clash <- function(added, existing, lazy) {
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

nis_comorbidity_warn_poa <- function(slots, existing) {
  missing <- slots$name[!is.na(slots$poa) & !slots$poa %in% existing]
  if (length(missing) > 0L) {
    missing_slots <- paste(missing, collapse = ", ")
    cli::cli_warn(c(
      "No matching POA column for {length(missing)} diagnosis slots: {missing_slots}. Assuming present.",
      i = "POA-dependent comorbidities may include conditions acquired in hospital."
    ))
  }
}

nis_comorbidity_warn_unusable <- function(count, systems) {
  if (count > 0L) {
    era <- paste(paste0("ICD-", systems), collapse = " or ")
    cli::cli_warn("{count} row{?s} {?has/have} no usable {era} code; comorbidity columns are `NA` for {?it/them}.")
  }
}
