nis_design_prepare_fields <- function(data) {
  if (!nis_is_duckdb(data)) {
    return(nis_sample_design_fields(data))
  }
  sql <- nis_design_validity_sql(data)
  columns <- c(nis_names(data), unname(.nis_design_invalid_fields), ".nis_valid")
  nis_sql_mutate(data, sql, columns)
}

nis_design_validity_sql <- function(data) {
  con <- dbplyr::remote_con(data)
  predicates <- nis_design_invalid_exprs(data)
  flags <- DBI::dbQuoteIdentifier(con, names(predicates))
  invalid <- vapply(
    predicates,
    function(expr) {
      as.character(dbplyr::translate_sql(!!expr, con = con, window = FALSE))
    },
    character(1)
  )
  sprintf(
    'SELECT *, NOT (%s) AS ".nis_valid" FROM (SELECT *, %s FROM (%s) AS sample) AS defects',
    paste(flags, collapse = " OR "),
    paste(paste(invalid, "AS", flags), collapse = ", "),
    dbplyr::sql_render(data)
  )
}

nis_sample_roster_sql <- function(prepared, quarters) {
  # Group invalid discharges by defect and known year so arbitrary bad IDs
  # cannot make the roster as large as the input.
  flags <- c(".nis_valid", unname(.nis_design_invalid_fields))
  fields <- c(
    DBI::dbQuoteIdentifier(dbplyr::remote_con(prepared), flags),
    'CASE WHEN NOT ".nis_bad_YEAR" THEN "YEAR" END AS "YEAR"',
    'CASE WHEN ".nis_valid" THEN "HOSP_NIS" END AS "HOSP_NIS"',
    'CASE WHEN ".nis_valid" THEN "NIS_STRATUM" END AS "NIS_STRATUM"',
    'min(CASE WHEN ".nis_valid" THEN CAST("DISCWT" AS DOUBLE) ELSE \'Infinity\'::DOUBLE END) AS "DISCWT"',
    'count(*) AS "n"',
    nis_sample_quarter_sql(quarters)
  )
  sprintf(
    "SELECT %s FROM (%s) AS prepared GROUP BY %s",
    paste(fields, collapse = ", "),
    dbplyr::sql_render(prepared),
    paste(seq_len(length(flags) + length(.nis_survey_keys)), collapse = ", ")
  )
}

nis_sample_quarter_sql <- function(prototype) {
  if (is.null(prototype)) {
    return(character())
  }
  quarter <- 1:4
  matches <- if (is.character(prototype) || is.factor(prototype)) {
    sprintf('"DQTR"::VARCHAR IN (\'%d\', \'Q%d\')', quarter, quarter)
  } else {
    sprintf('"DQTR" = %d', quarter)
  }
  sprintf('bool_or(".nis_valid" AND COALESCE(%s, FALSE)) AS ".nis_quarter_%d"', matches, quarter)
}

nis_design_cohort_sql <- function(data, selected) {
  fields <- DBI::dbQuoteIdentifier(dbplyr::remote_con(data), selected)
  sprintf(
    'SELECT %s FROM (%s) AS prepared WHERE ".nis_valid" AND ".nis_cohort"',
    paste(fields, collapse = ", "),
    dbplyr::sql_render(data)
  )
}
