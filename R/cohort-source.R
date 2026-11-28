nis_cohort_membership <- function(cohort, saved, call) {
  missing <- rlang::quo_is_missing(cohort)
  if (saved && !missing) {
    cli::cli_abort("Omit `cohort` when using a saved cohort.", call = call)
  }
  if (saved) {
    return(rlang::quo(.in_cohort))
  }
  if (missing) {
    cli::cli_abort("Supply a `cohort` expression for the source sample.", call = call)
  }
  nis_design_cohort_expr(cohort, call)
}

nis_saved_cohort <- function(query, call) {
  source <- nis_open_source_info(query)
  definitions <- source$definitions
  if (!length(definitions)) {
    return(NULL)
  }
  if (length(definitions) != length(source$paths) || anyNA(definitions) || length(unique(definitions)) != 1L) {
    cli::cli_abort("Open a saved cohort separately from other datasets.", call = call)
  }
  if (!".in_cohort" %in% nis_names(query)) {
    cli::cli_abort("Keep the `.in_cohort` membership column in a saved cohort query.", call = call)
  }
  definitions[[1L]]
}

nis_cohort_definitions <- function(con, paths) {
  # Group by path so duplicate footer entries cannot mask an unmarked part.
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT CASE WHEN count(*) = 1 THEN first(value::VARCHAR) END AS definition FROM parquet_kv_metadata(",
      nis_parquet_paths(con, paths),
      ") WHERE key = 'easyNIS_cohort'::BLOB GROUP BY file_name"
    )
  )$definition
}
