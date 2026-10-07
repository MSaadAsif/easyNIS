#' Report structural issues in an experimental import
#'
#' Checks identifiers, discharge weights, duplicate discharge keys, and code
#' column types without recoding the source values. Only aggregate issue counts
#' are returned. This report does not validate annual layouts, source counts,
#' conversion history, clinical phenotypes, survey methods, or disclosure safety.
#' User declarations of provenance remain unverified. A report without structural
#' errors is not an approved analysis input.
#'
#' @param data A relation returned by [nis_import()].
#' @return A `nis_validation` list with `issues`, `components`,
#'   `structural_errors`, `analysis_ready` (always `FALSE` in this prototype),
#'   `year`, and `scope`. Issues have severity, check, field, affected count,
#'   and message columns. A missing component is `"not_supplied"`, not a claim
#'   that it is unavailable in the original source.
#' @export
nis_validate <- function(data) {
  check_relation(data)
  con <- data$session$connection
  view <- sql_name(con, data$view)
  schema <- data$schema
  issues <- list()
  add <- function(severity, check, field = NA_character_, affected = NA_real_, message) {
    issues[[length(issues) + 1L]] <<- data.frame(
      severity = severity, check = check, field = field, affected = affected,
      message = message, stringsAsFactors = FALSE
    )
  }
  required <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
  for (field in setdiff(required, schema$column_name)) {
    add("error", "required_field_absent", field, message =
      "Required structural field absent; source/conversion omission is unverified.")
  }
  rows <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", view))
  if (rows == 0) add("error", "empty_core", affected = 0, message = "Core has no rows.")
  for (field in intersect(c("KEY_NIS", "HOSP_NIS", "NIS_STRATUM"), schema$column_name)) {
    type <- schema$column_type[match(field, schema$column_name)]
    bad <- identifier_problem_count(con, data$view, field, type)
    if (bad > 0) {
      add("error", "invalid_identifier", field, bad,
          "Missing, invalid, nonpositive, fractional, or precision-unsafe identifier.")
    }
  }
  if (all(c("YEAR", "KEY_NIS") %in% schema$column_name)) {
    duplicate_rows <- query_count(con, paste0("SELECT COALESCE(SUM(n - 1), 0) AS n FROM ",
      "(SELECT COUNT(*) AS n FROM ", view,
      " GROUP BY \"YEAR\", \"KEY_NIS\" HAVING COUNT(*) > 1) repeated_keys"))
    if (duplicate_rows > 0) {
      add("error", "duplicate_discharge_keys", "KEY_NIS", duplicate_rows,
          "Repeated YEAR/KEY_NIS keys; affected is the number of extra rows.")
    }
  }
  if ("DISCWT" %in% schema$column_name) {
    type <- schema$column_type[match("DISCWT", schema$column_name)]
    if (!sql_numeric_type(type)) {
      add("error", "weight_type", "DISCWT", message = "Discharge weight must be numeric.")
    } else {
      bad <- query_count(con, paste0("SELECT COUNT(*) AS n FROM ", view,
        " WHERE \"DISCWT\" IS NULL OR NOT isfinite(\"DISCWT\") OR \"DISCWT\" <= 0"))
      if (bad > 0) add("error", "invalid_discharge_weight", "DISCWT", bad,
                        "Modern annual discharge weights must be finite and positive.")
    }
  }
  code_fields <- schema$column_name[grepl("^I10_(DX|PR)[0-9]+$", schema$column_name)]
  if (!"I10_DX1" %in% code_fields) {
    add("warning", "principal_diagnosis_absent", "I10_DX1", message =
      "Principal diagnosis was not supplied; cohort capability is unavailable.")
  }
  for (field in code_fields) {
    if (schema$column_type[match(field, schema$column_name)] != "VARCHAR") {
      add("error", "code_type", field, message =
        "Code fields must be character strings; numeric conversion can lose leading zeros.")
    }
  }
  add("warning", "annual_layout_unverified", message =
    "Annual component layouts and release revision have not passed metadata review.")
  add("warning", "conversion_unverified", message =
    "Conversion history, prefiltering, labels, missing reasons, and derived tools need review.")
  issue_table <- do.call(rbind, issues)
  components <- data.frame(
    component = c("core", "hospital", "severity", "diagnosis_procedure_groups"),
    state = ifelse(c("core", "hospital", "severity", "diagnosis_procedure_groups") %in%
      names(data$sources), "supplied", "not_supplied"), stringsAsFactors = FALSE
  )
  structure(list(
    issues = issue_table, components = components,
    structural_errors = any(issue_table$severity == "error"), analysis_ready = FALSE,
    year = data$year, scope = data$validation_scope
  ), class = "nis_validation")
}

sql_numeric_type <- function(type) {
  grepl("^(U?(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT)|FLOAT|DOUBLE|DECIMAL\\()", type)
}

identifier_problem_count <- function(con, view, field, type) {
  quoted <- sql_name(con, field)
  invalid <- paste0(quoted, " IS NULL OR TRIM(CAST(", quoted, " AS VARCHAR)) = ''")
  if (sql_numeric_type(type)) {
    invalid <- paste0(invalid, " OR NOT isfinite(", quoted, ") OR ", quoted,
                      " <= 0 OR ", quoted, " != FLOOR(", quoted, ")")
    if (type %in% c("FLOAT", "DOUBLE")) {
      threshold <- if (type == "FLOAT") "16777216" else "9007199254740992"
      invalid <- paste0(invalid, " OR ABS(", quoted, ") >= ", threshold)
    }
  } else if (type != "VARCHAR") {
    return(query_count(con, paste0("SELECT COUNT(*) AS n FROM ", sql_name(con, view))))
  }
  query_count(con, paste0("SELECT COUNT(*) AS n FROM ", sql_name(con, view),
                          " WHERE ", invalid))
}
