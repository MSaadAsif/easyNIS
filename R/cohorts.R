#' Add an experimental code-set flag without filtering discharges
#'
#' Matches explicit source slots and retains all rows in a new lazy relation.
#' A positive match takes precedence over missing slots. Missing-policy choices
#' refer to null or blank selected slots, without inferring special missing
#' reasons. Records outside the declared quarters receive NA. The code-set
#' declaration and exact selected columns are retained in `flags` provenance.
#' Nonmissing observed codes must have complete system-compatible syntax before
#' matching. Malformed values fail with aggregate diagnostics, not a negative
#' flag. ASCII spaces, tabs, carriage returns and line feeds define blank slots.
#'
#' Annual slot metadata and clinical validity remain unverified. The default
#' slot policy uses observed available columns and records that choice. Specify
#' the same `slots` across years for a common-slot sensitivity analysis.
#'
#' @param data A relation returned by [nis_import()].
#' @param name A new flag column name. Existing fields cannot be overwritten,
#'   including case-insensitive collisions with imported fields and recorded
#'   flag definitions removed by [nis_select()]. Use a fresh name for a new set.
#' @param codes A declaration returned by [nis_code_set()].
#' @param scope Explicitly choose `"principal_diagnosis"`,
#'   `"secondary_diagnosis"`, `"any_diagnosis"`, or `"any_procedure"`.
#' @param missing Explicitly choose `"no_match"`, `"unknown_if_all_missing"`,
#'   or `"unknown_if_any_missing"`. Unknown flags are NA, not observed negatives.
#' @param slots Optional unique positive integer slot numbers. They must be
#'   present and compatible with the selected scope. `NULL` uses observed slots.
#' @return A new `nis_data` relation with a logical flag and its provenance.
#'   The original relation, source values, and complete discharge population
#'   are preserved. Clinical and analysis approval are not implied.
#' @export
#' @examples
#' session <- nis_open()
#' path <- tempfile(fileext = ".parquet")
#' core <- nis_synthetic_data()$core
#' core$I10_DX1 <- rep("A001", nrow(core)) # Invented test values.
#' DBI::dbWriteTable(session$connection, "invented", core)
#' DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'   DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#' stays <- nis_import(session, path, 2022)
#' codes <- nis_code_set("A001", "ICD10CM", 2022,
#'                       "invented-1", "invented example", "example")
#' flagged <- nis_flag_codes(stays, "condition", codes,
#'                           "principal_diagnosis", "no_match")
#' nis_collect(flagged, "condition", limit = 3)
#' nis_close(session)
#' unlink(path)
nis_flag_codes <- function(data, name, codes, scope, missing, slots = NULL) {
  check_relation(data)
  check_string(name, "name")
  if (tolower(name) %in% tolower(c(data$schema$column_name,
                                  data$import_schema$column_name, names(data$flags)))) {
    stop("Flag name conflicts with an existing or imported field or recorded definition.",
         call. = FALSE)
  }
  if (!inherits(codes, "nis_code_set")) {
    stop("`codes` must come from nis_code_set().", call. = FALSE)
  }
  if (!data$year %in% codes$valid_years) {
    stop("The code set does not declare applicability to this data year.", call. = FALSE)
  }
  if (base::missing(scope)) stop("Choose an explicit `scope`.", call. = FALSE)
  if (base::missing(missing)) stop("Choose an explicit `missing` policy.", call. = FALSE)
  scope <- match.arg(scope, c("principal_diagnosis", "secondary_diagnosis",
                              "any_diagnosis", "any_procedure"))
  missing <- match.arg(missing, c("no_match", "unknown_if_all_missing",
                                  "unknown_if_any_missing"))
  procedure <- scope == "any_procedure"
  if ((codes$system == "ICD10PCS") != procedure) {
    stop("Code-set system and diagnosis/procedure scope are incompatible.", call. = FALSE)
  }
  prefix <- if (procedure) "I10_PR" else "I10_DX"
  available <- data$schema$column_name[grepl(paste0("^", prefix, "[1-9][0-9]*$"),
                                           data$schema$column_name)]
  numbers <- as.double(sub(prefix, "", available, fixed = TRUE))
  allowed <- if (scope == "principal_diagnosis") numbers == 1L else if (
    scope == "secondary_diagnosis") numbers > 1L else rep(TRUE, length(numbers))
  available <- available[allowed]
  numbers <- numbers[allowed]
  if (!is.null(slots)) {
    validate_years(slots)
    if (!length(slots) || any(slots < 1L) || anyDuplicated(slots) ||
        any(!slots %in% numbers)) {
      stop("`slots` must be unique, present positive slot numbers allowed by the scope.",
           call. = FALSE)
    }
    selected <- available[match(sort(slots), numbers)]
  } else selected <- available[order(numbers)]
  if (!length(selected)) stop("No source slots are available for the chosen scope.", call. = FALSE)
  if (any(data$schema$column_type[match(selected, data$schema$column_name)] != "VARCHAR")) {
    stop("Matching requires character source slots; numeric codes cannot be recovered.",
         call. = FALSE)
  }
  con <- data$session$connection
  fields <- sql_name(con, selected)
  trimmed <- paste0("trim(", fields, ", chr(32) || chr(9) || chr(10) || chr(13))")
  candidates <- if (codes$normalize) paste0("upper(", trimmed, ")") else fields
  pattern <- if (procedure) "[0-9A-HJ-NP-Z]{7}" else
    "([A-Z][0-9][A-Z0-9]{1,5}|[A-Z][0-9][A-Z0-9][.][A-Z0-9]{1,4})"
  malformed <- paste0("(", fields, " IS NOT NULL AND ", trimmed,
    " != '' AND NOT regexp_full_match(", candidates, ", ",
    DBI::dbQuoteString(con, pattern), "))")
  bad_rows <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", sql_name(con, data$view),
                                     " WHERE ", paste(malformed, collapse = " OR ")))
  if (bad_rows > 0) {
    stop_structure_issue("invalid_code_syntax", "relation", selected, bad_rows,
      paste0("Selected source slots have malformed ", codes$system,
             " syntax in ", bad_rows, " rows; matching was not performed."))
  }
  transformed <- if (codes$normalize && !procedure) {
    paste0("replace(", candidates, ", '.', '')")
  } else candidates
  literals <- as.character(DBI::dbQuoteString(con, codes$matching_codes))
  slot_matches <- vapply(transformed, function(field) {
    if (codes$match == "exact") {
      paste0("COALESCE(", field, " IN (", paste(literals, collapse = ", "), "), FALSE)")
    } else paste0("(", paste(paste0("COALESCE(starts_with(", field, ", ", literals,
                                       "), FALSE)"), collapse = " OR "), ")")
  }, character(1))
  positive <- paste(slot_matches, collapse = " OR ")
  missing_fields <- paste0("(", fields, " IS NULL OR ", trimmed, " = '')")
  unknown <- switch(missing,
    no_match = "FALSE",
    unknown_if_all_missing = paste(missing_fields, collapse = " AND "),
    unknown_if_any_missing = paste(missing_fields, collapse = " OR ")
  )
  outside <- "FALSE"
  if (!identical(codes$valid_quarters, 1:4)) {
    require_fields(data$schema, "DQTR", "relation")
    invalid <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", sql_name(con, data$view),
      " WHERE TRY_CAST(\"DQTR\" AS DOUBLE) IS NULL OR ",
      "TRY_CAST(\"DQTR\" AS DOUBLE) NOT IN (1, 2, 3, 4)"))
    if (invalid > 0) stop("Restricted code-set quarters require valid DQTR values.", call. = FALSE)
    outside <- paste0("TRY_CAST(\"DQTR\" AS DOUBLE) NOT IN (",
                      paste(codes$valid_quarters, collapse = ", "), ")")
  }
  expression <- paste0("CASE WHEN ", outside, " THEN NULL WHEN ", positive,
                       " THEN TRUE WHEN ", unknown, " THEN NULL ELSE FALSE END")
  view <- next_view_name(data$session)
  DBI::dbExecute(con, paste0("CREATE TEMP VIEW ", sql_name(con, view),
    " AS SELECT *, ", expression, " AS ", sql_name(con, name),
    " FROM ", sql_name(con, data$view)))
  result <- data
  result$view <- view
  result$schema <- rbind(data$schema,
    data.frame(column_name = name, column_type = "BOOLEAN", stringsAsFactors = FALSE))
  result$flags[[name]] <- list(
    code_set = codes, scope = scope, missing = missing,
    slot_policy = if (is.null(slots)) "observed_available" else "explicit_common_slots",
    slots = selected, annual_slot_metadata = "unverified"
  )
  result
}
