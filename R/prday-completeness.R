#' Summarize procedure-day completeness by year and procedure slot
#'
#' Counts matched procedure slots with known, missing, negative/sentinel, or
#' absent PRDAY values. Prefix matching and day classification follow
#' [nis_flag_pr()] and [nis_flag_pr_timing()]; only slots whose procedure code
#' matches `pr` are counted. Counts are unweighted discharge-slot counts.
#' This is a descriptive completeness summary: it does not impute days or
#' judge whether the observed completeness is acceptable.
#'
#' @param .data A data frame or lazy Arrow or DuckDB query with `YEAR`.
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
#'   does not retain source-file field presence by year. When present, `NA`
#'   days count as missing and all negative days (including HCUP sentinels)
#'   count as sentinel/invalid, matching `nis_flag_pr_timing()`.
#' @export
#' @examples
#' toy <- data.frame(
#'   YEAR = c(2020L, 2020L, 2021L),
#'   I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ"),
#'   I10_PR2 = c("0JH604Z", "OTHER", "0JH604Z"),
#'   PRDAY1 = c(0L, -99L, 1L), PRDAY2 = c(1L, NA_integer_, -88L)
#' )
#' nis_prday_completeness(toy, c("02UG0", "0JH60"))
nis_prday_completeness <- function(.data, pr,
                                   system = c("icd10", "icd9")) {
  system <- match.arg(system)
  pr <- normalize_prefixes(pr, "pr") # nolint: object_usage_linter
  columns <- colnames(.data)
  if (!"YEAR" %in% columns) {
    cli::cli_abort("`.data` must contain a `YEAR` column.")
  }

  stem <- if (system == "icd10") "I10_PR" else "PR"
  procedure_names <- grep(paste0("^", stem, "[0-9]+$"),
    columns, value = TRUE)
  if (length(procedure_names) == 0L) {
    cli::cli_abort(paste0("No {if (system == 'icd10') 'ICD-10' else 'ICD-9'} PR columns (",
      stem, "<n>) were found."))
  }
  slots <- as.integer(sub(paste0("^", stem), "", procedure_names))
  order_slots <- order(slots)
  procedure_names <- procedure_names[order_slots]
  slots <- slots[order_slots]
  day_names <- grep("^PRDAY[0-9]+$", columns, value = TRUE)
  day_slots <- as.character(as.integer(sub("^PRDAY", "", day_names)))
  day_by_slot <- stats::setNames(day_names, day_slots)
  is_frame <- is.data.frame(.data)
  is_sql <- inherits(.data, "tbl_sql")
  projection <- if (is_frame || is_sql) NULL else
    dplyr::select(.data, dplyr::everything())$selected_columns
  matches <- lapply(procedure_names, function(column) {
    if (is_frame) {
      frame_match(pr, column)
    } else if (is_sql) {
      reduce_or(lapply(pr, function(prefix) {
        rlang::expr(starts_with(as.character(!!rlang::sym(column)), !!prefix))
      }))
    } else {
      arrow_match(pr, projection[column])
    }
  })
  eligibility <- code_system_filter(columns, "PR", system) # nolint: object_usage_linter
  if (!is.null(eligibility)) {
    matches <- lapply(matches, function(match) {
      rlang::expr((!!eligibility) & (!!match))
    })
  }

  summaries <- lapply(seq_along(slots), function(i) {
    slot <- slots[[i]]
    match <- matches[[i]]
    day_name <- unname(day_by_slot[as.character(slot)])
    counts <- list(
      matched_slots = rlang::expr(sum(as.integer(!!match), na.rm = TRUE))
    )
    if (length(day_name) == 0L || is.na(day_name)) {
      counts$known_day <- rlang::expr(0L)
      counts$missing_day <- rlang::expr(0L)
      counts$sentinel_invalid_day <- rlang::expr(0L)
      counts$absent_prday_column <- rlang::expr(sum(as.integer(!!match), na.rm = TRUE))
    } else {
      day <- rlang::sym(day_name)
      counts$known_day <- rlang::expr(sum(as.integer(!!match & !is.na(!!day) & !!day >= 0), na.rm = TRUE))
      counts$missing_day <- rlang::expr(sum(as.integer(!!match & is.na(!!day)), na.rm = TRUE))
      counts$sentinel_invalid_day <- rlang::expr(sum(as.integer(!!match & !is.na(!!day) & !!day < 0), na.rm = TRUE))
      counts$absent_prday_column <- rlang::expr(0L)
    }
    .data |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(!!!counts, .groups = "drop") |>
      nis_collect() |>
      dplyr::mutate(slot = as.integer(slot), .before = 1L)
  })
  output <- dplyr::bind_rows(summaries) |>
    dplyr::mutate(pct_known = dplyr::if_else(matched_slots == 0L, NA_real_,
      100 * known_day / matched_slots)) |>
    dplyr::select(YEAR, slot, matched_slots, known_day, missing_day,
      sentinel_invalid_day, absent_prday_column, pct_known) |>
    dplyr::arrange(YEAR, slot)
  output
}
