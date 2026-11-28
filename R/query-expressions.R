reduce_or <- function(terms) {
  Reduce(function(left, right) rlang::expr((!!left) | (!!right)), terms)
}

nis_gate_expr <- function(condition, value) {
  # Code-system predicates handle missing inputs explicitly. A single WHEN
  # avoids dbplyr emitting the same condition again for the false branch.
  rlang::expr(dplyr::case_when(!!condition ~ !!value, .default = FALSE))
}

nis_is_nonnegative_integer <- function(threshold) {
  if (!identical(length(threshold), 1L) || !is.numeric(threshold)) {
    return(FALSE)
  }
  !is.na(threshold) &&
    is.finite(threshold) &&
    threshold >= 0 &&
    threshold <= .Machine$integer.max &&
    threshold == as.integer(threshold)
}

nis_names <- function(data) {
  if (inherits(data, "tbl_sql")) colnames(data) else names(data)
}

nis_is_duckdb <- function(data) {
  inherits(data, "tbl_sql") && inherits(dbplyr::remote_con(data), "duckdb_connection")
}

nis_retain_sql_source <- function(result, data) {
  result$src <- data$src
  if (inherits(data, "tbl_nis")) {
    class(result) <- unique(c("tbl_nis", class(result)))
  }
  result
}

nis_sql_result <- function(data, sql, columns) {
  result <- dplyr::tbl(dbplyr::remote_con(data), dbplyr::sql(sql), vars = columns)
  nis_retain_sql_source(result, data)
}

nis_sql_mutate <- function(data, sql, columns) {
  result <- nis_sql_result(data, sql, columns)
  result <- dplyr::group_by(result, !!!rlang::syms(dplyr::group_vars(data)))
  # Keep the caller's window context when adding fields to its rows.
  result$lazy_query$order_vars <- dbplyr::op_sort(data)
  result$lazy_query$frame <- dbplyr::op_frame(data)
  result
}

nis_select_columns <- function(data, selection, error_call = rlang::caller_call(), exclude = character()) {
  lazy <- inherits(data, "tbl_sql")
  if (lazy) {
    columns <- setdiff(colnames(data), exclude)
    data <- stats::setNames(vector("list", length(columns)), columns)
  }
  names(tidyselect::eval_select(
    selection,
    data,
    allow_rename = FALSE,
    allow_predicates = !lazy,
    error_call = error_call
  ))
}

nis_is_finite_expr <- function(data, column) {
  if (inherits(data, "tbl_sql")) {
    value <- if (inherits(column, "sql")) column else dbplyr::ident(column)
    return(dbplyr::sql_expr(isfinite(!!value), con = data$src$con))
  }
  rlang::expr(is.finite(!!rlang::sym(column)))
}

nis_is_positive_finite_expr <- function(data, column) {
  value <- if (inherits(column, "sql")) column else rlang::sym(column)
  finite <- nis_is_finite_expr(data, column)
  rlang::expr(!!finite & !!value > 0)
}

nis_is_missing_expr <- function(data, column) {
  value <- rlang::sym(column)
  if (inherits(data, "tbl_sql")) {
    numeric_types <- c(
      "TINYINT",
      "SMALLINT",
      "INTEGER",
      "BIGINT",
      "HUGEINT",
      "UTINYINT",
      "USMALLINT",
      "UINTEGER",
      "UBIGINT",
      "UHUGEINT",
      "FLOAT",
      "REAL",
      "DOUBLE",
      "DECIMAL"
    )
    identifier <- as.character(DBI::dbQuoteIdentifier(data$src$con, column))
    types <- paste(as.character(DBI::dbQuoteString(data$src$con, numeric_types)), collapse = ", ")
    return(dbplyr::sql(paste0(
      "(",
      identifier,
      " IS NULL OR (typeof(",
      identifier,
      ") IN (",
      types,
      ") AND isnan(TRY_CAST(",
      identifier,
      " AS DOUBLE))))"
    )))
  }
  rlang::expr(is.na(!!value))
}

nis_internal_names <- function(data, reserved, candidates) {
  if (!inherits(data, "tbl_sql")) {
    return(utils::tail(make.unique(c(reserved, candidates)), length(candidates)))
  }
  keys <- nis_sql_identifier_key(c(reserved, candidates))
  unique_keys <- make.unique(keys)
  candidate_keys <- utils::tail(keys, length(candidates))
  suffix <- substring(utils::tail(unique_keys, length(candidates)), nchar(candidate_keys) + 1L)
  paste0(candidates, suffix)
}

nis_sql_identifier_key <- function(names) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", names)
}

nis_collect <- function(x) {
  if (is.data.frame(x)) {
    return(x)
  }
  if (inherits(x, "tbl_sql")) {
    con <- dbplyr::remote_con(x)
    if (inherits(con, "duckdb_connection") && !inherits(con, "nis_duckdb_connection")) {
      nis_collect_check(con, dbplyr::sql_render(x))
    }
  }
  nis_duckdb_translate_errors(dplyr::collect(x))
}
