# Run after capture.R <evidence> prday-fixture 2.
prday_expected <- function() {
  id <- 0:49999
  offset <- outer(id, 1:25, `+`)
  present <- offset %% 19L < 3L
  present[, 1L] <- TRUE
  index <- present & offset %% 2L == 0L
  outcome <- present & !index
  day <- offset %% 9L
  day[offset %% 31L == 0L] <- NA

  index_days <- day
  index_days[!index] <- NA
  earliest <- do.call(pmin, c(as.data.frame(index_days), list(na.rm = TRUE)))
  later <- day - earliest
  yes <- rowSums(outcome & later >= 0 & later <= 3, na.rm = TRUE) > 0
  unknown <- rowSums(index) > 0 & rowSums(outcome) > 0 & rowSums(present & is.na(day)) > 0
  audit <- data.frame(
    matched_slots = colSums(outcome),
    known_day = colSums(outcome & !is.na(day)),
    missing_day = colSums(outcome & is.na(day)),
    sentinel_invalid_day = 0L,
    absent_prday_column = 0L
  )
  list(yes = sum(yes) * 5L, unknown = sum(!yes & unknown) * 5L, audit = audit)
}

prday_gate <- function(root) {
  options(easyNIS.duckdb_config = list(threads = "2", memory_limit = "2GB"))
  pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)
  input <- easyNIS::nis_open(file.path(root, "invented"), check_release = FALSE)
  con <- dbplyr::remote_con(input)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  expected <- prday_expected()
  stopifnot(expected$yes > 0L, expected$unknown > 0L, expected$yes + expected$unknown < 250000L)
  clock <- function() proc.time()[["elapsed"]]
  results <- lapply(seq_len(3L), function(run) {
    start <- clock()
    query <- easyNIS::nis_flag_pr_timing(
      input,
      "0270",
      "02L73",
      relation = "within_days",
      window = 3L,
      missing_day = "indeterminate"
    )
    sql <- paste(
      "SELECT count(*) AS rows, count(*) FILTER (WHERE outcome_post_index) AS yes,",
      "count(*) FILTER (WHERE outcome_post_index IS NULL) AS unknown FROM (",
      dbplyr::sql_render(query),
      ") n"
    )
    rendered <- clock()
    DBI::dbExecute(con, paste("PREPARE prday_gate AS", sql))
    prepared <- clock()
    result <- DBI::dbGetQuery(con, "EXECUTE prday_gate")
    finished <- clock()
    DBI::dbExecute(con, "DEALLOCATE prday_gate")
    stopifnot(result$rows == 250000L, result$yes == expected$yes, result$unknown == expected$unknown)
    audit_start <- clock()
    audit <- easyNIS::nis_audit_prday(input, "02L73")
    audit_time <- clock() - audit_start
    stopifnot(identical(audit$YEAR, rep(2017:2021, each = 25L)), identical(audit$slot, rep(1:25, 5L)))
    counts <- expected$audit[rep(1:25, 5L), ]
    stopifnot(all(as.matrix(audit[, names(counts)]) == as.matrix(counts)))
    stopifnot(all(audit$pct_known == 100 * counts$known_day / counts$matched_slots))
    c(
      run = run,
      build_render = rendered - start,
      prepare = prepared - rendered,
      execute = finished - prepared,
      timing_total = finished - start,
      audit_total = audit_time
    )
  })
  times <- do.call(rbind, results)
  print(times)
  cat("Verified 250000 flags and 125 year/slot cells. TRUE:", expected$yes, "NULL:", expected$unknown, "\n")
  medians <- apply(times[, -1L], 2L, stats::median)
  budget <- c(build_render = 3, prepare = 1, execute = 4, timing_total = 7, audit_total = 7)
  if (any(medians > budget)) {
    stop("PRDAY seconds exceeded budget in: ", paste(names(budget)[medians > budget], collapse = ", "))
  }
}

prday_gate(commandArgs(TRUE)[[1L]])
