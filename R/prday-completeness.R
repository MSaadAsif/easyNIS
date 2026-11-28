#' Check procedure-day completeness
#'
#' Counts matched procedure slots with known, missing, negative/sentinel, or
#' absent PRDAY values. Prefix matching and day classification follow
#' [nis_flag_pr()] and [nis_flag_pr_timing()]; only slots whose procedure code
#' matches `pr` are counted. Counts are unweighted discharge-slot counts.
#' This is a descriptive completeness summary: it does not impute days or
#' judge whether the observed completeness is acceptable.
#'
#' @param .data A data frame or lazy DuckDB query with `YEAR`.
#' @param pr Character vector of procedure code prefixes, normalized and
#'   matched under the same rules as [nis_flag_pr()].
#' @param system Code system: `"icd10"` uses `I10_PR<n>` (default); `"icd9"`
#'   uses `PR<n>`.
#'
#' @return An in-memory tibble with one row per year and procedure slot.
#'   `matched_slots` counts matching procedure slots; `known_day`,
#'   `missing_day`, `sentinel_invalid_day`, and `absent_prday_column` partition
#'   those matches. `pct_known` is `100 * known_day / matched_slots`, or `NA`
#'   when there are no matched slots. A PRDAY column is considered absent when
#'   it is absent from the input query's schema. A unified multi-file query
#'   does not retain source-file field presence by year. A value that does not
#'   decode to a finite number counts as missing. Factor days use their
#'   labels. Negative finite days (including HCUP sentinels) count as
#'   sentinel/invalid, matching `nis_flag_pr_timing()`.
#' @family cohort-definition
#' @seealso [Defining cohorts](https://msaadasif.github.io/easyNIS/articles/cohorts.html).
#' @export
#' @examples
#' nis <- nis_open(nis_example(2020)) |>
#'   dplyr::mutate(PRDAY1 = 0L, PRDAY2 = 1L)
#' nis_audit_prday(nis, pr = "0270")
nis_audit_prday <- function(.data, pr, system = c("icd10", "icd9")) {
  system <- match.arg(system)
  pr <- normalize_prefixes(pr, "pr")
  columns <- nis_names(.data)
  if (!"YEAR" %in% columns) {
    cli::cli_abort("`.data` must contain a `YEAR` column.")
  }

  layout <- nis_procedure_slots(columns, system, rlang::current_call())
  rule <- nis_prefix_rule(pr)
  eligibility <- code_system_filter(.data, columns, "PR", system)
  summary <- if (nis_is_duckdb(.data)) {
    nis_prday_audit_sql(.data, layout, rule, eligibility)
  } else {
    counts <- nis_prday_count_expressions(.data, layout, rule, eligibility)
    .data |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(!!!counts, .groups = "drop")
  }
  nis_prday_summary(nis_collect(summary), layout$slot)
}

nis_prday_audit_sql <- function(data, layout, rule, eligibility) {
  con <- dbplyr::remote_con(data)
  year <- DBI::dbQuoteIdentifier(con, "YEAR")
  pos <- seq_along(layout$slot)
  matches <- DBI::dbQuoteIdentifier(con, paste0("pr_match_", pos))
  days <- DBI::dbQuoteIdentifier(con, paste0("pr_day_", pos))
  matched <- nis_code_match_sql(con, rule, layout$procedure)
  matched <- nis_code_eligible_sql(con, eligibility, matched)
  decoded <- nis_prday_day_sql(con, columns = layout$day)
  fields <- c(year, sprintf("%s AS %s", matched, matches), sprintf("%s AS %s", decoded, days))
  counts <- lapply(pos, function(i) {
    nis_prday_slot_counts_sql(matches[[i]], days[[i]], is.na(layout$day[[i]]), i)
  })
  counts <- unlist(counts)
  sql <- sprintf(
    "SELECT %s, %s FROM (SELECT %s FROM (\n%s\n) AS prday_source) AS prday_slots GROUP BY %s",
    year,
    paste(sprintf("%s AS %s", counts, DBI::dbQuoteIdentifier(con, names(counts))), collapse = ", "),
    paste(fields, collapse = ", "),
    dbplyr::sql_render(data),
    year
  )
  nis_sql_result(data, sql, c("YEAR", names(counts)))
}

nis_prday_slot_counts_sql <- function(match, day, absent, pos) {
  count <- function(predicate) sprintf("sum(CASE WHEN %s THEN 1 ELSE 0 END)", predicate)
  nis_prday_count_fields(
    count(match),
    absent,
    zero = "0",
    pos = pos,
    known = count(paste0(match, " AND ", day, " >= 0")),
    missing = count(paste0(match, " AND ", day, " IS NULL")),
    sentinel = count(paste0(match, " AND ", day, " < 0"))
  )
}

nis_prday_count_expressions <- function(data, layout, rule, eligibility) {
  counts <- lapply(seq_along(layout$slot), function(pos) {
    match <- nis_in_code_system(nis_code_match(rule, data, layout$procedure[[pos]]), eligibility)
    day <- layout$day[[pos]]
    decoded <- nis_procedure_day(day, data)
    count <- function(predicate) rlang::expr(sum(as.integer(!!predicate), na.rm = TRUE))
    nis_prday_count_fields(
      count(match),
      is.na(day),
      zero = rlang::expr(0L),
      pos = pos,
      known = count(rlang::expr(!!match & (!!decoded$known))),
      missing = count(rlang::expr(!!match & (!!decoded$missing))),
      sentinel = count(rlang::expr(!!match & (!!decoded$sentinel)))
    )
  })
  do.call(c, counts)
}

nis_prday_metrics <- c("matched_slots", "known_day", "missing_day", "sentinel_invalid_day", "absent_prday_column")

nis_prday_count_fields <- function(total, absent, zero, pos, known, missing, sentinel) {
  counts <- if (absent) list(total, zero, zero, zero, total) else list(total, known, missing, sentinel, zero)
  stats::setNames(counts, paste0(nis_prday_metrics, "__", pos))
}

nis_prday_summary <- function(wide, slots) {
  summaries <- lapply(seq_along(slots), function(i) {
    suffix <- paste0("__", i)
    summary <- data.frame(YEAR = wide$YEAR, slot = rep(slots[[i]], nrow(wide)))
    for (metric in nis_prday_metrics) {
      summary[[metric]] <- as.integer(wide[[paste0(metric, suffix)]])
    }
    dplyr::as_tibble(summary)
  })
  dplyr::bind_rows(summaries) |>
    dplyr::mutate(
      pct_known = dplyr::if_else(
        matched_slots == 0L,
        NA_real_,
        100 * known_day / matched_slots
      )
    ) |>
    dplyr::arrange(YEAR, slot)
}
