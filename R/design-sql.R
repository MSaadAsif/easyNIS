nis_design_duckdb <- function(data) {
  inherits(data, "tbl_sql") && inherits(dbplyr::remote_con(data), "duckdb_connection")
}

nis_design_sql_tbl <- function(data, sql, columns) {
  out <- dplyr::tbl(dbplyr::remote_con(data), dbplyr::sql(sql), vars = columns)
  out$src <- data$src
  out
}

nis_design_prepare_fields <- function(data) {
  if (!nis_design_duckdb(data)) {
    return(nis_sample_design_fields(data))
  }
  sql <- nis_design_validity_sql(data)
  columns <- c(nis_names(data), unname(.nis_design_invalid_fields), ".nis_valid")
  out <- nis_design_sql_tbl(data, sql, columns)
  # Keep the caller's window context for annual-total membership expressions.
  out$lazy_query$order_vars <- dbplyr::op_sort(data)
  out$lazy_query$frame <- dbplyr::op_frame(data)
  out
}

nis_design_validity_sql <- function(data) {
  con <- dbplyr::remote_con(data)
  fields <- DBI::dbQuoteIdentifier(con, .nis_design_fields)
  flags <- DBI::dbQuoteIdentifier(con, unname(.nis_design_invalid_fields))
  invalid <- sprintf("NOT COALESCE(isfinite(%s) AND %s > 0, FALSE) AS %s", fields, fields, flags)
  sprintf(
    'SELECT *, NOT (%s) AS ".nis_valid" FROM (SELECT *, %s FROM (%s) AS sample) AS defects',
    paste(flags, collapse = " OR "),
    paste(invalid, collapse = ", "),
    dbplyr::sql_render(data)
  )
}

nis_sample_roster_sql <- function(prepared, quarters = NULL, valid_only = FALSE) {
  keys <- c('"YEAR"', '"HOSP_NIS"', '"NIS_STRATUM"')
  if (valid_only) {
    fields <- c(keys, 'min(CAST("DISCWT" AS DOUBLE)) AS "DISCWT"')
    where <- 'WHERE ".nis_valid"'
  } else {
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
    keys <- c(flags, keys)
    where <- ""
  }
  sprintf(
    "SELECT %s FROM (%s) AS prepared %s GROUP BY %s",
    paste(fields, collapse = ", "),
    dbplyr::sql_render(prepared),
    where,
    paste(seq_along(keys), collapse = ", ")
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
