# Summarize the recorded runs. Keep raw CSV and JSON as the source of truth.
args <- commandArgs(TRUE)
root <- args[[1]]
dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
dirs <- dirs[file.exists(file.path(dirs, "summary.csv"))]
read <- function(path) read.csv(path, check.names = FALSE)
scan_nodes <- function(x, full = FALSE) {
  kind <- if (is.null(x$operator_name)) "" else trimws(x$operator_name)
  here <- grepl("PARQUET|ARROW_SCAN", kind) && !grepl("METADATA", kind)
  if (full && here) {
    files_read <- x$extra_info[["Total Files Read"]]
    here <- identical(as.character(files_read), "5") &&
      length(x$operator_rows_scanned) == 1L &&
      x$operator_rows_scanned >= 2500000
  }
  as.integer(here) + sum(vapply(x$children, scan_nodes, 0L, full = full))
}
sum_part <- function(x, part) sum(x$ms[x$part == part])
rows <- lapply(dirs, function(path) {
  s <- read(file.path(path, "summary.csv"))
  file <- function(name) file.path(path, name)
  e <- if (file.exists(file("events.csv"))) {
    read(file("events.csv"))
  } else {
    data.frame(part = character(), ms = numeric(), sql = character())
  }
  logged <- list.files(path, "^duckdb-log-.*[.]csv$", full.names = TRUE)
  log_count <- sum(vapply(
    logged,
    function(f) {
      msg <- read(f)$message
      sum(!grepl("^(PRAGMA enable_profiling|SET profiling_|SELECT [*] FROM duckdb_logs)", msg, ignore.case = TRUE))
    },
    0L
  ))
  files <- list.files(path, "^query-.*[.]json$", full.names = TRUE)
  profiles <- lapply(files, jsonlite::read_json, simplifyVector = FALSE)
  scans <- sum(vapply(profiles, scan_nodes, 0L))
  full_scans <- sum(vapply(profiles, scan_nodes, 0L, full = TRUE))
  peak_buffer <- max(c(0, unlist(lapply(profiles, "[[", "system_peak_buffer_memory"))))
  peak_tmp <- max(c(0, unlist(lapply(profiles, "[[", "system_peak_temp_dir_size"))))
  cpu <- sum(unlist(lapply(profiles, "[[", "cpu_time"))) * 1000
  proc <- paste0(path, ".process.json")
  peak <- if (file.exists(proc)) jsonlite::read_json(proc)$peak_commit_bytes
  commit <- if (length(peak)) peak / 2^20 else NA_real_
  plan <- sum_part(e, "prepare")
  run <- sum_part(e, "execute")
  render <- sum_part(e, "render")
  # Counts include only statements started by the entry point.
  phase <- data.frame(
    s,
    render,
    plan,
    run,
    other = s$ms - plan - run - render,
    log_count,
    scans,
    full_scans,
    profiles = length(profiles),
    commit,
    buffer_mib = peak_buffer / 2^20,
    spill_mib = peak_tmp / 2^20,
    cpu,
    collect_checks = sum_part(e, "nis_collect_check"),
    release = sum_part(e, "nis_open_check_release"),
    key_check = sum_part(e, "nis_cmrb_validate_keys"),
    connect = sum_part(e, "connect"),
    finalizer = sum_part(e, "nis_duckdb_attach_finalizer"),
    build_design = sum_part(e, "nis_design_build"),
    prototype = sum_part(e, "nis_design_fields"),
    validation = sum_part(e, "nis_convert_validate_batch")
  )
  phase
})
all <- do.call(rbind, rows)
write.csv(all, file.path(root, "baseline-summary.csv"), row.names = FALSE)
print(all[, setdiff(names(all), "status")], row.names = FALSE, digits = 3)
