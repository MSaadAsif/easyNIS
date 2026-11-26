args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
trial <- args[[1L]]
writeLines(as.character(Sys.getpid()), file.path(trial, "pid"))
source("tools/experiments/in-database-survey/workload.R")
options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE,
  survey.multicore = FALSE, na.action = "na.omit")

run_trial <- function(trial, root, end_year, threads, memory_mb, backend, call) {
  years <- 2018:end_year
  files <- lapply(file.path(root, sprintf("NIS_%d.parquet", years)), list.files,
    pattern = "\\.parquet$", full.names = TRUE)
  stopifnot(all(lengths(files) == 4L))
  paths <- normalizePath(unlist(files), winslash = "/", mustWork = TRUE)
  spill <- file.path(trial, "spill")
  dir.create(spill)
  start <- proc.time()[["elapsed"]]
  con <- DBI::dbConnect(duckdb::duckdb(config = list(
    threads = as.character(threads), memory_limit = paste(memory_mb, "MB"),
    temp_directory = spill, preserve_insertion_order = "false")))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  settings <- DBI::dbGetQuery(con, paste(
    "SELECT current_setting('threads') AS threads,",
    "current_setting('memory_limit') AS memory_limit,",
    "current_setting('temp_directory') AS temp_directory"))
  limit <- strsplit(settings$memory_limit, " ", fixed = TRUE)[[1L]]
  limit_bytes <- as.numeric(limit[[1L]]) * c(MiB = 1024^2, GiB = 1024^3)[limit[[2L]]]
  stopifnot(settings$threads == threads, abs(limit_bytes / (memory_mb * 1e6) - 1) < 0.02,
    normalizePath(settings$temp_directory, winslash = "/") ==
      normalizePath(spill, winslash = "/"))
  write.table(settings, file.path(trial, "settings.tsv"), sep = "\t", row.names = FALSE)
  spec <- workloads[[call]]
  open_views(con, paths, wide = isTRUE(spec$wide))
  if (call == "audit") {
    audit <- DBI::dbGetQuery(con, sprintf(paste(
      "SELECT count(*) AS input_rows,",
      "count(*) FILTER (WHERE NOT (%1$s)) AS excluded_rows,",
      "%2$s,",
      "count(DISTINCT filename) AS files,",
      "bool_and(NOT (%1$s) OR YEAR = try_cast(regexp_extract(filename,",
      "'NIS_(20[0-9]{2})[.]parquet', 1) AS INTEGER)) AS year_ok,",
      "bool_and(NOT (%1$s) OR (YEAR BETWEEN 2018 AND %3$d AND YEAR = trunc(YEAR)",
      "AND HOSP_NIS = trunc(HOSP_NIS) AND HOSP_NIS < 1000000",
      "AND NIS_STRATUM = trunc(NIS_STRATUM) AND NIS_STRATUM < 1000000)) AS keys_ok",
      "FROM raw_input"), valid_design, paste(sprintf(
      "count(*) FILTER (WHERE NOT coalesce(isfinite(%1$s) AND %1$s > 0, false)) AS invalid_%1$s",
      design_fields), collapse = ", "), end_year))
    saveRDS(audit, file.path(trial, "audit.rds"))
    stopifnot(audit$year_ok, audit$keys_ok, audit$files == length(paths))
    return(invisible(NULL))
  }

  profile_path <- file.path(trial, "duckdb-profile.json")
  DBI::dbExecute(con, "SET enable_profiling = 'json'")
  DBI::dbExecute(con, "SET profiling_coverage = 'ALL'")
  DBI::dbExecute(con, paste("SET profiling_output =", DBI::dbQuoteString(con, profile_path)))
  profiles <- list()
  # A fresh JSON file is required for every data query. Record DuckDB's peak
  # for transient spills that the Windows directory sampler could miss.
  query <- function(sql, execute = FALSE) {
    unlink(profile_path)
    result <- if (execute) {
      DBI::dbExecute(con, sql)
      data.frame()
    } else DBI::dbGetQuery(con, sql)
    if (!file.exists(profile_path)) stop("DuckDB did not profile the data query.")
    p <- jsonlite::fromJSON(profile_path, simplifyVector = FALSE)
    stopifnot(length(p$system_peak_temp_dir_size) == 1L,
      length(p$system_peak_buffer_memory) == 1L)
    profiles[[length(profiles) + 1L]] <<- data.frame(rows = nrow(result),
      buffer_bytes = p$system_peak_buffer_memory, temp_bytes = p$system_peak_temp_dir_size)
    result
  }
  before_call <- proc.time()[["elapsed"]]
  if (backend %in% c("sql_view", "sql_temp")) {
    materialize <- if (backend == "sql_temp") function(sql) {
      start_materialize <- proc.time()[["elapsed"]]
      query(paste("CREATE TEMP TABLE model_input AS", sql), execute = TRUE)
      writeLines(as.character(proc.time()[["elapsed"]] - start_materialize),
        file.path(trial, "materialize-seconds.txt"))
      "model_input"
    }
    result <- sql_call(query, call, years, materialize)
    stopifnot(all(vapply(profiles, function(x) x$rows <= length(years), logical(1))))
  } else {
    columns <- unique(c(design_fields, spec$y,
      if (!is.null(spec$domain) || !is.null(spec$family)) c("AGE", "FEMALE"),
      if (isTRUE(spec$wide)) wide_columns))
    data <- query(paste("SELECT", paste(columns, collapse = ", "), "FROM valid"))
    design <- reference_design(data)
    rm(data)
    result <- reference_call(design, call)
  }
  elapsed <- proc.time()[["elapsed"]]
  stopifnot(all(is.finite(result$estimate)), all(is.finite(result$se)))
  if (identical(workloads[[call]]$group, "YEAR")) {
    stopifnot(identical(names(result$estimate), as.character(years)))
  }
  saveRDS(result, file.path(trial, "statistics.rds"))
  write.table(do.call(rbind, profiles), file.path(trial, "queries.tsv"),
    sep = "\t", row.names = FALSE)
  writeLines(as.character(c(before_call - start, elapsed - before_call)),
    file.path(trial, "elapsed.txt"))
  invisible(NULL)
}

tryCatch({
  run_trial(trial, args[[2L]], as.integer(args[[3L]]), as.integer(args[[4L]]),
    as.integer(args[[5L]]), args[[6L]], args[[7L]])
  status <- "ok"
}, error = function(e) {
  writeLines(conditionMessage(e), file.path(trial, "error.txt"))
  status <<- "error"
})
writeLines(status, file.path(trial, "done"))
for (i in seq_len(200L)) {
  if (file.exists(file.path(trial, "sampled"))) break
  Sys.sleep(0.05)
}
quit(status = as.integer(status != "ok"))
