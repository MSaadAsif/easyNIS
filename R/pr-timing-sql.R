timing_query_sql <- function(data, specs, columns, name, relation, window, missing_day) {
  con <- dbplyr::remote_con(data)
  flags <- nis_internal_names(data, c(columns, name), paste0(".nis_timing_flag_", seq_along(specs)))
  reserved <- c(columns, name, flags)
  source <- dbplyr::sql_render(data)
  for (i in seq_along(specs)) {
    source <- timing_system_sql(data, con, source, specs[[i]], reserved, flags[[i]], relation, window, missing_day)
  }
  fields <- DBI::dbQuoteIdentifier(con, columns)
  flag <- paste(DBI::dbQuoteIdentifier(con, flags), collapse = " OR ")
  sprintf(
    "SELECT %s, (%s) AS %s FROM (\n%s\n) AS timing_flags",
    paste(fields, collapse = ", "),
    flag,
    DBI::dbQuoteIdentifier(con, name),
    source
  )
}

timing_system_sql <- function(data, con, source, spec, reserved, flag, relation, window, missing_day) {
  layout <- spec$layout
  pos <- seq_along(layout$procedure)
  n <- length(pos)
  aliases <- nis_internal_names(
    data,
    reserved,
    c(
      paste0(".nis_timing_index_", pos),
      paste0(".nis_timing_outcome_", pos),
      paste0(".nis_timing_day_", pos),
      ".nis_timing_min_index_day"
    )
  )
  ids <- DBI::dbQuoteIdentifier(con, aliases)
  index <- ids[pos]
  outcome <- ids[n + pos]
  days <- ids[2L * n + pos]
  earliest <- ids[[3L * n + 1L]]
  match <- lapply(spec$rules, function(rule) nis_code_match_sql(con, rule, layout$procedure))
  usable <- nis_prday_day_sql(con, layout$day, nonnegative = TRUE)
  if (missing_day == "assume_same_day") {
    usable <- sprintf("COALESCE(%s, 0)", usable)
  }
  fields <- sprintf("%s AS %s", c(match[[1L]], match[[2L]], usable), ids[seq_len(3L * n)])
  candidates <- sprintf("CASE WHEN %s THEN %s END", index, days)
  result <- timing_result_sql(index, outcome, days, earliest, relation, window, missing_day)
  result <- nis_code_eligible_sql(con, spec$eligibility, result)
  sprintf(
    paste(
      "SELECT * EXCLUDE (%s), %s AS %s",
      "FROM (SELECT *, LEAST(%s) AS %s",
      "FROM (SELECT *, %s FROM (\n%s\n) AS timing_source) AS timing_slots) AS timing_index"
    ),
    paste(ids, collapse = ", "),
    result,
    DBI::dbQuoteIdentifier(con, flag),
    paste(candidates, collapse = ", "),
    earliest,
    paste(fields, collapse = ", "),
    source
  )
}

timing_result_sql <- function(index, outcome, days, earliest, relation, window, missing_day) {
  disjunction <- function(terms) paste(terms, collapse = " OR ")
  comparison <- timing_relation_sql(days, earliest, relation, window)
  success <- sprintf("COALESCE(%s, FALSE)", disjunction(sprintf("(%s AND %s)", outcome, comparison)))
  if (missing_day != "indeterminate") {
    return(success)
  }
  unknown <- sprintf("((%s OR %s) AND %s IS NULL)", index, outcome, days)
  sprintf(
    "CASE WHEN %s THEN TRUE WHEN (%s) AND (%s) AND (%s) THEN NULL ELSE FALSE END",
    success,
    disjunction(index),
    disjunction(outcome),
    disjunction(unknown)
  )
}

timing_relation_sql <- function(days, earliest, relation, window) {
  switch(
    relation,
    on_or_after = sprintf("%s >= %s", days, earliest),
    after = sprintf("%s > %s", days, earliest),
    before = sprintf("%s < %s", days, earliest),
    same_day = sprintf("%s = %s", days, earliest),
    within_days = sprintf("(%s - %s) BETWEEN 0 AND %d", days, earliest, window)
  )
}
