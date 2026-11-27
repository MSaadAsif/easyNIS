#' Summarize procedure-day completeness by year and procedure slot
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
  summary <- if (nis_prday_duckdb(.data)) {
    nis_prday_audit_sql(.data, layout, columns, pr, system)
  } else {
    counts <- nis_prday_count_expressions(.data, layout, columns, pr, system)
    .data |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(!!!counts, .groups = "drop")
  }
  nis_prday_summary(nis_collect(summary), layout$slot)
}

nis_prday_audit_sql <- function(data, layout, columns, pr, system) {
  con <- dbplyr::remote_con(data)
  year <- DBI::dbQuoteIdentifier(con, "YEAR")
  pos <- seq_along(layout$slot)
  matches <- DBI::dbQuoteIdentifier(con, paste0("pr_match_", pos))
  days <- DBI::dbQuoteIdentifier(con, paste0("pr_day_", pos))
  eligibility <- code_system_filter(data, columns, "PR", system)
  matched <- nis_prday_match_sql(con, nis_prefix_rule(pr), layout$procedure)
  matched <- nis_prday_eligible_sql(con, eligibility, matched)
  decoded <- nis_prday_day_sql(con, columns = layout$day)
  fields <- c(year, sprintf("%s AS %s", matched, matches), sprintf("%s AS %s", decoded, days))
  counts <- lapply(pos, function(i) {
    nis_prday_slot_counts_sql(matches[[i]], days[[i]], is.na(layout$day[[i]]), i)
  })
  counts <- do.call(c, counts)
  sql <- sprintf(
    "SELECT %s, %s FROM (SELECT %s FROM (\n%s\n) AS prday_source) AS prday_slots GROUP BY %s",
    year,
    paste(sprintf("%s AS %s", counts, DBI::dbQuoteIdentifier(con, names(counts))), collapse = ", "),
    paste(fields, collapse = ", "),
    dbplyr::sql_render(data),
    year
  )
  nis_prday_tbl(data, sql, c("YEAR", names(counts)))
}

nis_prday_slot_counts_sql <- function(match, day, absent, pos) {
  count <- function(predicate) sprintf("sum(CASE WHEN %s THEN 1 ELSE 0 END)", predicate)
  matched <- count(match)
  counts <- c(
    matched_slots = matched,
    known_day = if (absent) "0" else count(paste0(match, " AND ", day, " >= 0")),
    missing_day = if (absent) "0" else count(paste0(match, " AND ", day, " IS NULL")),
    sentinel_invalid_day = if (absent) "0" else count(paste0(match, " AND ", day, " < 0")),
    absent_prday_column = if (absent) matched else "0"
  )
  stats::setNames(counts, paste0(names(counts), "__", pos))
}

nis_prday_count_expressions <- function(.data, layout, columns, pr, system) {
  slots <- layout$slot
  matches <- lapply(layout$procedure, function(column) {
    nis_code_match(nis_prefix_rule(pr), .data, column)
  })
  eligibility <- code_system_filter(.data, columns, "PR", system)
  matches <- lapply(matches, nis_in_code_system, eligibility = eligibility)

  counts <- list()
  for (i in seq_along(slots)) {
    match <- matches[[i]]
    day_name <- layout$day[[i]]
    suffix <- paste0("__", i)
    counts[[paste0("matched_slots", suffix)]] <-
      rlang::expr(sum(as.integer(!!match), na.rm = TRUE))
    if (is.na(day_name)) {
      counts[[paste0("known_day", suffix)]] <- rlang::expr(0L)
      counts[[paste0("missing_day", suffix)]] <- rlang::expr(0L)
      counts[[paste0("sentinel_invalid_day", suffix)]] <- rlang::expr(0L)
      counts[[paste0("absent_prday_column", suffix)]] <-
        rlang::expr(sum(as.integer(!!match), na.rm = TRUE))
    } else {
      decoded <- nis_procedure_day(day_name, .data)
      counts[[paste0("known_day", suffix)]] <- rlang::expr(
        sum(as.integer(!!match & (!!decoded$known)), na.rm = TRUE)
      )
      counts[[paste0("missing_day", suffix)]] <- rlang::expr(
        sum(as.integer(!!match & (!!decoded$missing)), na.rm = TRUE)
      )
      counts[[paste0("sentinel_invalid_day", suffix)]] <- rlang::expr(
        sum(as.integer(!!match & (!!decoded$sentinel)), na.rm = TRUE)
      )
      counts[[paste0("absent_prday_column", suffix)]] <- rlang::expr(0L)
    }
  }
  counts
}

nis_prday_summary <- function(wide, slots) {
  metrics <- c("matched_slots", "known_day", "missing_day", "sentinel_invalid_day", "absent_prday_column")
  summaries <- lapply(seq_along(slots), function(i) {
    suffix <- paste0("__", i)
    summary <- data.frame(YEAR = wide$YEAR, slot = rep(slots[[i]], nrow(wide)))
    for (metric in metrics) {
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
    dplyr::select(
      YEAR,
      slot,
      matched_slots,
      known_day,
      missing_day,
      sentinel_invalid_day,
      absent_prday_column,
      pct_known
    ) |>
    dplyr::arrange(YEAR, slot)
}
