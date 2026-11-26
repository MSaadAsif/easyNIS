source("tools/experiments/in-database-survey/workload.R")
run <- commandArgs(TRUE)[[1L]]
metrics <- read.delim(file.path(run, "metrics.tsv"))
metrics <- metrics[metrics$call != "audit", ]
if (!nrow(metrics)) quit()
result_path <- function(trial) file.path(run, trial, "statistics.rds")
successful <- metrics[metrics$status == "ok", ]
reference <- successful[successful$backend == "survey", ]
sql <- successful[startsWith(successful$backend, "sql_"), ]
agreement <- do.call(rbind, lapply(seq_len(nrow(sql)), function(i) {
  row <- sql[i, ]
  peers <- sql[sql$end_year == row$end_year & sql$call == row$call & sql$trial != row$trial &
    (sql$profile != row$profile | sql$backend != row$backend), ]
  expected <- list("SQL across paths or profiles" = head(peers$trial, 1L))
  if (row$end_year == 2020) expected$survey <- reference$trial[reference$call == row$call]
  actual <- readRDS(result_path(row$trial))
  do.call(rbind, lapply(names(expected), function(comparison) {
    trials <- expected[[comparison]]
    if (!length(trials)) return(NULL)
    diff <- Reduce(pmax, lapply(trials, function(trial) {
      differences(actual, readRDS(result_path(trial)))
    }))
    data.frame(trial = row$trial, call = row$call, comparison = comparison,
      t(diff), pass = all(diff <= 1e-6))
  }))
}))
if (!is.null(agreement)) {
  write.table(agreement, file.path(run, "agreement.tsv"), sep = "\t", row.names = FALSE)
}
cells <- split(metrics, metrics[c("end_year", "profile", "backend", "call")], drop = TRUE)
summary <- do.call(rbind, lapply(cells, function(cell) {
  ok <- cell[cell$status == "ok", ]
  checks <- agreement[agreement$trial %in% ok$trial, , drop = FALSE]
  data.frame(call = cell$call[1], end_year = cell$end_year[1], profile = cell$profile[1],
    backend = cell$backend[1], successful = nrow(ok), attempted = nrow(cell),
    wall_s = median(ok$wall_s), call_s = median(ok$call_s),
    materialize_s = median(ok$materialize_s),
    peak_commit_GB = max(cell$peak_commit_bytes) / 1e9,
    peak_ws_GB = max(cell$peak_ws_bytes) / 1e9,
    spill_bytes = max(c(ok$sampled_temp_bytes, ok$duckdb_peak_temp_bytes, 0), na.rm = TRUE),
    residual_bytes = max(cell$residual_temp_bytes), residual_files = max(cell$residual_temp_files),
    agreement = if (!NROW(checks)) NA_character_ else if (all(checks$pass)) "pass" else "fail")
}))
write.table(summary, file.path(run, "summary.tsv"), sep = "\t", row.names = FALSE)
quit(status = as.integer(any(metrics$status != "ok") || any(!agreement$pass)))
