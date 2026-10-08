#' Select columns without collecting or filtering discharges
#'
#' Creates a new lazy relation with exactly the requested columns in order.
#' Every discharge is retained. Raw import schema and flag definitions remain
#' in provenance so [nis_validate()] can identify fields removed by selection.
#' Source files and the original relation are unchanged. No column is renamed,
#' harmonized, or recoded.
#'
#' @param data A relation returned by [nis_import()] or [nis_flag_codes()].
#' @param columns A non-empty character vector of unique exact column names.
#' @return A new `nis_data` relation. `selections` records the requested columns
#'   for each selection step. An omitted field cannot be collected or used for
#'   matching until the caller returns to a relation that contains it.
#' @export
#' @examples
#' session <- nis_open()
#' path <- tempfile(fileext = ".parquet")
#' DBI::dbWriteTable(session$connection, "invented", nis_synthetic_data()$core)
#' DBI::dbExecute(session$connection, paste0("COPY invented TO ",
#'   DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
#' stays <- nis_import(session, path, 2022)
#' narrow <- nis_select(stays, c("KEY_NIS", "AGE"))
#' nis_validate(narrow, c("AGE", "DISCWT", "UNDECLARED_FIELD"))$fields
#' nis_collect(narrow, "AGE", limit = 3)
#' nis_close(session)
#' unlink(path)
nis_select <- function(data, columns) {
  check_relation(data)
  check_projection(data, columns)
  con <- data$session$connection
  view <- next_view_name(data$session)
  DBI::dbExecute(con, paste0("CREATE TEMP VIEW ", sql_name(con, view), " AS SELECT ",
    paste(sql_name(con, columns), collapse = ", "), " FROM ", sql_name(con, data$view)))
  result <- data
  result$view <- view
  result$schema <- data$schema[match(columns, data$schema$column_name), , drop = FALSE]
  rownames(result$schema) <- NULL
  result$selections <- c(data$selections, list(columns))
  result
}
