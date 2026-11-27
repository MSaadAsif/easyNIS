nis_procedure_slots <- function(columns, system, error_call) {
  stem <- nis_code_stem("PR", system)
  slots <- nis_code_slots(columns, stem, canonical = FALSE)
  if (!length(slots)) {
    cli::cli_abort(
      paste0("No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} PR columns (", stem, "<n>) were found."),
      call = error_call
    )
  }
  positions <- order(as.integer(slots), seq_along(slots))
  slot <- as.integer(slots[positions])
  days <- nis_code_slots(columns, "PRDAY", canonical = FALSE)
  list(
    procedure = names(slots)[positions],
    slot = slot,
    day = as.character(names(days))[match(slot, as.integer(days))],
    has_days = length(days) > 0L
  )
}

nis_procedure_day <- function(column, data) {
  decoded <- nis_decode_procedure_day(column, data)
  day <- decoded$value
  missing <- decoded$missing
  known <- rlang::expr(!(!!missing) & !!day >= 0)
  sentinel <- rlang::expr(!(!!missing) & !!day < 0)
  list(
    missing = missing,
    known = known,
    sentinel = sentinel,
    usable = rlang::expr(dplyr::case_when(!!known ~ !!day))
  )
}

nis_decode_procedure_day <- function(column, data) {
  if (is.na(column)) {
    return(list(value = rlang::expr(NA_real_), missing = rlang::expr(TRUE)))
  }
  field <- rlang::sym(column)
  if (inherits(data, "tbl_sql")) {
    value <- nis_prday_cast_sql(dbplyr::remote_con(data), column)
    return(list(
      value = dbplyr::sql(value),
      missing = dbplyr::sql(paste0("(", value, " IS NULL OR NOT isfinite(", value, "))"))
    ))
  }
  if (is.data.frame(data) && is.factor(data[[column]])) {
    field <- rlang::expr(as.character(!!field))
  }
  value <- rlang::expr(as.double(!!field))
  list(value = value, missing = rlang::expr(!is.finite(!!value)))
}

nis_prday_duckdb <- function(data) {
  inherits(data, "tbl_sql") && inherits(dbplyr::remote_con(data), "duckdb_connection")
}

nis_prday_cast_sql <- function(con, columns) {
  sprintf("TRY_CAST(%s AS DOUBLE)", DBI::dbQuoteIdentifier(con, columns))
}

nis_prday_day_sql <- function(con, columns, nonnegative = FALSE) {
  days <- rep("NULL::DOUBLE", length(columns))
  present <- !is.na(columns)
  cast <- nis_prday_cast_sql(con, columns[present])
  condition <- sprintf("isfinite(%s)", cast)
  if (nonnegative) {
    condition <- sprintf("%s AND %s >= 0", condition, cast)
  }
  days[present] <- sprintf("CASE WHEN %s THEN %s END", condition, cast)
  days
}

nis_prday_match_sql <- function(con, rule, columns) {
  identifiers <- DBI::dbQuoteIdentifier(con, columns)
  prefixes <- DBI::dbQuoteString(con, rule$prefix)
  regexes <- DBI::dbQuoteString(con, rule$regex)
  exclusions <- DBI::dbQuoteString(con, rule$exclude)
  vapply(
    identifiers,
    function(column) {
      value <- sprintf("TRY_CAST(%s AS VARCHAR)", column)
      tests <- c(
        if (length(prefixes)) sprintf("substr(%s, 1, %d) = %s", column, nchar(rule$prefix), prefixes),
        if (length(regexes)) sprintf("regexp_full_match(%s, %s)", value, regexes)
      )
      match <- paste0("COALESCE(", paste(tests, collapse = " OR "), ", FALSE)")
      if (length(exclusions)) {
        match <- sprintf("(%s AND NOT COALESCE(%s IN (%s), FALSE))", match, value, paste(exclusions, collapse = ", "))
      }
      match
    },
    character(1)
  )
}

nis_prday_eligible_sql <- function(con, condition, result) {
  if (is.null(condition)) {
    return(result)
  }
  predicate <- dbplyr::translate_sql(!!condition, con = con, window = FALSE)
  sprintf("CASE WHEN %s THEN %s ELSE FALSE END", predicate, result)
}

nis_prday_tbl <- function(data, sql, columns) {
  out <- dplyr::tbl(dbplyr::remote_con(data), dbplyr::sql(sql), vars = columns)
  out$src <- data$src
  if (inherits(data, "tbl_nis")) {
    class(out) <- c("tbl_nis", class(out))
  }
  out
}
