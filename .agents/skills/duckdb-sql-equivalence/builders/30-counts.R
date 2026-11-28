valid_design <- function(rows) {
  fields <- rows[c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")]
  bad <- as.data.frame(lapply(fields, function(x) !is.finite(x) | x <= 0))
  list(ok = rowSums(bad) == 0L, bad = bad)
}

design_cases <- function(con) {
  rows <- fixture(
    YEAR = c(0, 2019, 2020, NA, NaN, Inf),
    HOSP_NIS = c(0, 1, 2, NA, Inf),
    NIS_STRATUM = c(0, 1, NA, Inf),
    DISCWT = c(-9, 0, 1, 4, NA, NaN, Inf),
    DQTR = c(1L, 2L, 3L, 4L, NA),
    keep = c(FALSE, TRUE, NA)
  )
  text <- rows
  text$DQTR <- c("1", "Q2", "3", "Q4")[text$DQTR]
  list(case(rows), case(text))
}

design_output <- function(cohort, hospitals, bad, coverage, input_rows) {
  hospital <- hospitals[order(hospitals$YEAR, hospitals$HOSP_NIS), ]
  out <- data.frame(
    kind = c(
      rep("cohort", length(cohort)),
      rep("min-weight", nrow(hospital)),
      rep("invalid", length(bad)),
      rep("quarter", nrow(coverage)),
      "input-rows"
    ),
    key = c(
      sort(cohort),
      paste(hospital$YEAR, hospital$HOSP_NIS, sep = ":"),
      names(bad),
      paste(coverage$YEAR, coverage$quarter, sep = ":"),
      ""
    ),
    result = as.double(c(rep(1, length(cohort)), hospital$DISCWT, bad, rep(1, nrow(coverage)), input_rows))
  )
  out[order(out$kind, out$key), ]
}

design_sql <- function(con, rows, args) {
  sample <- internal("nis_design_sample")(
    duck_table(con, rows),
    rlang::quo(keep),
    "id",
    rows$DQTR[integer()],
    annualize = FALSE,
    call = rlang::caller_call()
  )
  coverage <- data.frame(YEAR = rep(sample$years, lengths(sample$coverage)), quarter = unlist(sample$coverage))
  bad <- setNames(sample$excluded$by_field, c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT"))
  design_output(sample$cohort_rows$id, sample$hospital_rows, bad, coverage, sample$input_rows)
}

design_reference <- function(rows, args) {
  valid <- valid_design(rows)
  sample <- rows[valid$ok, ]
  hospital <- stats::aggregate(DISCWT ~ YEAR + HOSP_NIS, sample, min)
  coverage <- unique(sample[!is.na(sample$DQTR), c("YEAR", "DQTR")])
  coverage$DQTR <- as.integer(sub("^Q", "", coverage$DQTR))
  names(coverage)[2L] <- "quarter"
  coverage <- coverage[order(coverage$YEAR, coverage$quarter), ]
  design_output(sample$id[sample$keep %in% TRUE], hospital, colSums(valid$bad), coverage, nrow(rows))
}

design_years <- function(case) {
  pair <- split_years(case)
  pair$combine <- function(outputs) {
    rows <- do.call(rbind, outputs)
    summarized <- stats::aggregate(result ~ kind + key, rows, sum)
    summarized[order(summarized$kind, summarized$key), ]
  }
  pair
}

register(
  "design-sample",
  design_cases,
  design_sql,
  design_reference,
  mutation("design-sql.R", "nis_sample_roster_sql", "min(CASE", "max(CASE"),
  relations = list(years = design_years, rows = shuffle_rows),
  relation_case = function(cases) {
    x <- cases[[1L]]
    x$rows <- x$rows[x$rows$YEAR %in% c(2019, 2020), ]
    x
  }
)

attrition_cases <- function(con) {
  result <- design_cases(con)
  rows <- subset(result[[1L]]$rows, YEAR %in% c(2019, 2020) & !is.infinite(DISCWT))
  rows$DX1 <- rep(c("A0", "Q", NA), length.out = nrow(rows))
  rows$I10_DX1 <- rep(c("B0", "A0", NA), length.out = nrow(rows))
  configs <- grid(by_year = c(TRUE, FALSE), design = c(TRUE, FALSE))
  lapply(seq_len(nrow(configs)), function(i) {
    case(rows, as.list(configs[i, ]))
  })
}

attrition_sql <- function(con, rows, args) {
  out <- as.data.frame(easyNIS::nis_attrition(
    duck_table(con, rows),
    keep = keep,
    by_year = args$by_year,
    .design = args$design,
    .codes = list(
      coded = list(type = "dx", position = "principal", system = "both", codes = list(icd9 = "A", icd10 = "B"))
    )
  ))
  attributes(out) <- attributes(out)[c("names", "row.names", "class")]
  if (args$by_year) {
    out <- out[order(out$YEAR, out$step), ]
  }
  out
}

attrition_reference <- function(rows, args) {
  if (args$design) {
    rows <- rows[valid_design(rows)$ok, ]
  }
  years <- if (args$by_year) sort(unique(rows$YEAR)) else NA_real_
  outputs <- lapply(years, function(y) {
    x <- if (args$by_year) rows[rows$YEAR == y, ] else rows
    coded <- x$I10_DX1 %in% "B0"
    accepted <- list(rep(TRUE, nrow(x)), x$keep %in% TRUE, x$keep %in% TRUE & coded)
    n <- vapply(accepted, function(keep) sum(keep), integer(1))
    w <- vapply(accepted, function(keep) sum(x$DISCWT[keep], na.rm = TRUE), double(1))
    baseline <- if (args$design) "Valid design discharges" else "All discharges"
    result <- data.frame(
      step = 0:2,
      criterion = c(baseline, "keep", "coded"),
      n_unweighted = n,
      n_dropped_unweighted = c(NA_integer_, -diff(n)),
      n_weighted = w,
      n_dropped_weighted = c(NA_real_, -diff(w)),
      pct_retained = if (n[1L] == 0L) NA_real_ else 100 * n / n[1L]
    )
    if (args$by_year) cbind(YEAR = y, result) else result
  })
  do.call(rbind, outputs)
}

register(
  "attrition",
  attrition_cases,
  attrition_sql,
  attrition_reference,
  mutation("attrition.R", ".nis_attrition_keep_exprs", "(!!previous) &", "(!!previous) |"),
  relations = list(years = split_years, rows = shuffle_rows),
  approximate = "pct_retained"
)

cell_cases <- function(con) {
  rows <- fixture(YEAR = 2019:2020, HOSP_NIS = 1:3, cell = c(NA, "a", "b"), copy = 1:2)
  lapply(list(c("YEAR", "cell"), "cell", character()), function(by) case(rows, list(by = by)))
}

cell_output <- function(result, by) {
  result[c("n", "hospitals")] <- lapply(result[c("n", "hospitals")], as.integer)
  if (length(by)) {
    result <- result[do.call(order, unname(result[by])), ]
  }
  result
}

cell_sql <- function(con, rows, args) {
  by <- args$by
  cell_output(as.data.frame(easyNIS::nis_cell_counts(duck_table(con, rows), by = tidyselect::all_of(by))), by)
}

cell_reference <- function(rows, args) {
  by <- args$by
  grouping <- if (length(by)) do.call(paste, c(rows[by], sep = ":")) else rep("all", nrow(rows))
  result <- lapply(split(seq_len(nrow(rows)), grouping), function(i) {
    x <- rows[i, ]
    cbind(x[1L, by, drop = FALSE], n = nrow(x), hospitals = nrow(unique(x[c("YEAR", "HOSP_NIS")])))
  })
  cell_output(do.call(rbind, result), by)
}

register(
  "cell-counts",
  cell_cases,
  cell_sql,
  cell_reference,
  mutation("cell-counts.R", "nis_hospital_count_query", "sum(!!discharges, na.rm = TRUE)", "dplyr::n()"),
  relations = list(years = split_years, rows = shuffle_rows)
)
