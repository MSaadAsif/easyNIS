#!/usr/bin/env Rscript

source(file.path("tools", "probe", "workspace.R"))
source(file.path("tools", "probe", "git-evidence.R"))
source(file.path("tools", "probe", "performance-results.R"))

performance_usage <- function() {
  stop("Usage: Rscript --vanilla tools/probe/probe-performance.R [--real | --smoke]", call. = FALSE)
}

performance_files <- function(path) {
  files <- list.files(path, all.files = TRUE, full.names = TRUE, recursive = TRUE)
  c(bytes = sum(file.size(files), na.rm = TRUE), files = length(files))
}

performance_process <- function(args, scratch, log) {
  processx::process$new(
    file.path(R.home("bin"), "Rterm.exe"),
    c("--vanilla", "--slave", "-f", file.path("tools", "probe", "performance-child.R"), "--args", args),
    stdout = log,
    stderr = "2>&1",
    env = c(
      "current",
      TMPDIR = scratch,
      TMP = scratch,
      TEMP = scratch,
      EASYNIS_PERFORMANCE_SCRATCH = scratch,
      OPENBLAS_NUM_THREADS = "1",
      OMP_NUM_THREADS = "1"
    ),
    cleanup_tree = TRUE,
    windows_hide_window = TRUE
  )
}

performance_measure <- function(run_dir, trial, max_commit, repeat_id) {
  id <- paste(trial$profile, trial$step, repeat_id, sep = "-")
  scratch <- file.path(run_dir, "scratch")
  runtime <- file.path(scratch, id)
  dir.create(runtime)
  on.exit(unlink(runtime, recursive = TRUE), add = TRUE)
  request <- file.path(scratch, "trial.rds")
  result <- file.path(scratch, "result.rds")
  unlink(result)
  saveRDS(trial, request)
  log <- if (is.na(trial$rows)) "NUL" else file.path(run_dir, paste0(id, ".txt"))
  started <- proc.time()[["elapsed"]]
  child <- performance_process(c(request, result), runtime, log)
  on.exit(if (child$is_alive()) child$kill_tree(), add = TRUE, after = FALSE)
  handle <- tryCatch(ps::ps_handle(child$get_pid()), error = function(cnd) NULL)
  peak_commit <- peak_temp <- 0
  stopped <- FALSE
  while (child$is_alive()) {
    sampled <- tryCatch(ps::ps_memory_info(handle)[["peak_pagefile"]], error = function(cnd) NA_real_)
    peak_commit <- max(peak_commit, sampled, na.rm = TRUE)
    peak_temp <- max(peak_temp, performance_files(runtime)[["bytes"]])
    if (peak_commit > max_commit) {
      child$kill_tree()
      stopped <- TRUE
      break
    }
    child$wait(50L)
  }
  child$wait()
  process_s <- proc.time()[["elapsed"]] - started
  observed <- if (file.exists(result)) readRDS(result) else list(wall = NA_real_, commit_bytes = NA_real_)
  remaining <- performance_files(runtime)
  status <- if (stopped) {
    "commit_limit"
  } else {
    switch(as.character(child$get_exit_status()), `0` = "ok", `76` = "host_capacity", "error")
  }
  data.frame(
    profile = trial$profile,
    step = trial$step,
    repeat_id = repeat_id,
    status = status,
    wall_s = observed$wall,
    process_s = process_s,
    commit_bytes = max(peak_commit, observed$commit_bytes, na.rm = TRUE),
    temp_bytes = max(peak_temp, remaining[["bytes"]]),
    remaining_files = remaining[["files"]]
  )
}

run_performance_probe <- function(mode) {
  if (.Platform$OS.type != "windows") {
    stop("The performance probe requires Windows process peak commit counters.", call. = FALSE)
  }
  run_dir <- probe_run_directory(probe_workspace(), "performance")
  cat("EVIDENCE", run_dir, "\n")
  scratch <- file.path(run_dir, "scratch")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  git <- git_evidence()
  rows <- switch(mode, invented = 7000000L, real = NA_integer_, smoke = 30000L)
  repeats <- if (mode == "smoke") 1L else performance_repeats
  years <- 2017:2022
  path <- if (mode == "real") Sys.getenv("EASYNIS_DATA") else file.path(scratch, "invented")
  if (mode == "real" && !dir.exists(path)) {
    stop("EASYNIS_DATA must point to the local NIS data directory.", call. = FALSE)
  }
  packages <- c("easyNIS", "DBI", "duckdb", "survey", "dplyr", "gtsummary", "ps", "processx")
  library <- file.path(scratch, "library")
  dir.create(library)
  callr::rcmd(
    "INSTALL",
    c(paste0("--library=", library), "."),
    stdout = file.path(run_dir, "install.txt"),
    stderr = "2>&1",
    fail_on_status = TRUE
  )
  if (mode != "real") {
    child <- performance_process(
      c("fixture", path, as.character(rows)),
      scratch,
      file.path(run_dir, "fixture.txt")
    )
    child$wait()
    if (child$get_exit_status() != 0L) stop("Invented fixture generation failed.", call. = FALSE)
  }
  jsonlite::write_json(
    c(
      git,
      list(
        mode = mode,
        rows_per_year = rows,
        repeats = repeats,
        years = years,
        command = paste(
          c("Rscript --vanilla tools/probe/probe-performance.R", commandArgs(trailingOnly = TRUE)),
          collapse = " "
        ),
        platform = R.version$platform,
        r = R.version.string,
        host_shared = TRUE,
        logical_cores = parallel::detectCores(),
        physical_ram_bytes = unname(ps::ps_system_memory()[["total"]]),
        versions = setNames(
          lapply(packages, function(package) {
            as.character(utils::packageVersion(package, lib.loc = c(library, .libPaths())))
          }),
          packages
        )
      )
    ),
    file.path(run_dir, "performance-manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  steps <- expand.grid(step = performance_steps, profile = names(performance_profiles), stringsAsFactors = FALSE)
  metrics <- list()
  for (repeat_id in seq_len(repeats)) {
    order <- seq_len(nrow(steps))
    if (repeat_id %% 2L == 0L) {
      order <- rev(order)
    }
    for (index in order) {
      trial <- c(as.list(steps[index, ]), list(path = path, years = years, rows = rows, library = library))
      limits <- performance_profiles[[trial$profile]]
      trial <- c(trial, limits[c("threads", "memory")])
      metric <- performance_measure(run_dir, trial, limits$commit_bytes, repeat_id)
      metrics[[length(metrics) + 1L]] <- metric
      utils::write.table(do.call(rbind, metrics), file.path(run_dir, "trials.tsv"), sep = "\t", row.names = FALSE)
      cat(trial$profile, trial$step, repeat_id, metric$status, "\n")
    }
  }
  summary <- performance_summary(do.call(rbind, metrics))
  if (!identical(git_evidence(), git)) {
    stop("Git evidence changed while the probe was running.", call. = FALSE)
  }
  utils::write.table(summary, file.path(run_dir, "summary.tsv"), sep = "\t", row.names = FALSE)
  if (mode != "real") {
    print(summary, row.names = FALSE)
  }
  if (mode == "smoke") {
    stopifnot(all(summary$completed == repeats), all(summary$remaining_files == 0L))
  } else {
    print(performance_assess(do.call(rbind, metrics)), row.names = FALSE)
  }
}

args <- commandArgs(trailingOnly = TRUE)
mode <- if (!length(args)) {
  "invented"
} else if (identical(args, "--real")) {
  "real"
} else if (identical(args, "--smoke")) {
  "smoke"
} else {
  performance_usage()
}
run_performance_probe(mode)
