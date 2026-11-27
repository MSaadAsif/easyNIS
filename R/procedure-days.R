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
    usable = rlang::expr(dplyr::if_else(!!known, !!day, NA_real_))
  )
}

nis_decode_procedure_day <- function(column, data) {
  if (is.na(column)) {
    return(list(value = rlang::expr(NA_real_), missing = rlang::expr(TRUE)))
  }
  field <- rlang::sym(column)
  if (inherits(data, "tbl_sql")) {
    identifier <- DBI::dbQuoteIdentifier(dbplyr::remote_con(data), column)
    value <- paste0("TRY_CAST(", identifier, " AS DOUBLE)")
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
