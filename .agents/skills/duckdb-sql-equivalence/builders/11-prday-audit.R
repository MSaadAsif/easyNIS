prday_audit_cases <- function(con) {
  rows <- fixture(
    YEAR = c(2014L, 2015L, 2020L, NA_integer_),
    PRVER = c(9L, 10L, NA_integer_),
    DQTR = c(3L, 4L, NA_integer_),
    I10_PR1 = c(NA, "I", "OUT"),
    I10_PR2 = c(NA, "I", "OUT"),
    PRDAY1 = c(NA, "bad", "-9", "0", ".5", "1", "Inf", "NaN"),
    PRDAY2 = c(NA, "bad", "-9", "0", ".5", "1", "Inf", "NaN")
  )
  legacy <- rows
  names(legacy) <- sub("^I10_PR", "PR", names(legacy))
  absent <- rows[setdiff(names(rows), "PRDAY2")]
  list(
    case(rows, list(system = "icd10")),
    case(legacy, list(system = "icd9")),
    case(absent, list(system = "icd10")),
    case(absent[setdiff(names(absent), "PRDAY1")], list(system = "icd10")),
    case(rows[FALSE, ], list(system = "icd10"))
  )
}

prday_audit_order <- function(x) x[order(x$YEAR, x$slot), , drop = FALSE]

prday_audit_reference <- function(rows, args) {
  years <- unique(rows$YEAR)
  system <- args$system
  counts <- lapply(1:2, function(slot) {
    code <- rows[[slot_names("PR", system, 2L)[[slot]]]]
    raw <- rows[[paste0("PRDAY", slot)]]
    matched <- !is.na(code) & startsWith(code, "OUT") & eligible(rows, system, "PR")
    year_count <- function(hit) {
      vapply(years, function(year) as.integer(sum(hit & rows$YEAR %in% year)), integer(1))
    }
    missing <- invalid <- known <- absent <- rep(FALSE, nrow(rows))
    if (is.null(raw)) {
      absent <- matched
    } else {
      day <- suppressWarnings(as.numeric(raw))
      missing <- matched & !is.finite(day)
      invalid <- matched & is.finite(day) & day < 0
      known <- matched & is.finite(day) & day >= 0
    }
    data.frame(
      YEAR = years,
      slot = rep(slot, length(years)),
      matched_slots = year_count(matched),
      known_day = year_count(known),
      missing_day = year_count(missing),
      sentinel_invalid_day = year_count(invalid),
      absent_prday_column = year_count(absent)
    )
  })
  result <- do.call(rbind, counts)
  result$pct_known <- 100 * result$known_day / result$matched_slots
  result$pct_known[result$matched_slots == 0L] <- NA_real_
  prday_audit_order(result)
}

prday_audit_slots <- function(case) {
  swapped <- case
  swapped$rows <- slot_swap(case$rows, c("I10_PR", "PRDAY"))
  # Relabel the swapped output to compare counts on the original slot labels.
  swapped$args$swapped <- TRUE
  list(left = list(swapped), right = list(case))
}

prday_audit_sql <- function(con, rows, args) {
  summary <- easyNIS::nis_audit_prday(duck_table(con, rows), "OUT", system = args$system)
  if (isTRUE(args$swapped)) {
    summary$slot <- 3L - summary$slot
  }
  prday_audit_order(as.data.frame(summary))
}

prday_audit_years <- function(case) {
  pair <- split_years(case)
  pair$combine <- function(outputs) prday_audit_order(do.call(rbind, outputs))
  pair
}

register(
  "prday-audit",
  prday_audit_cases,
  prday_audit_sql,
  prday_audit_reference,
  mutation("prday-completeness.R", "nis_prday_slot_counts_sql", " >= 0", " > 0"),
  relations = list(slots = prday_audit_slots, years = prday_audit_years, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[1L]]
    x$rows <- x$rows[x$rows$PRDAY1 %in% "0" & x$rows$PRDAY2 %in% "-9", ]
    x
  },
  relation_mutations = list(
    slots = mutation(
      "prday-completeness.R",
      "nis_prday_audit_sql",
      "columns = layout$day",
      "columns = rep(layout$day[[1L]], length(layout$day))"
    )
  )
)
