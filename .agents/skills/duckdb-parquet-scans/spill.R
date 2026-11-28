#!/usr/bin/env Rscript

source(".agents/skills/verify/runner.R")

make_sort_fixture <- function(path, rows) {
  con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = "2")))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (part in 0:3) {
    year <- 2019L + part %/% 2L
    directory <- file.path(path, paste0("YEAR=", year))
    if (!dir.exists(directory)) stopifnot(dir.create(directory))
    output <- DBI::dbQuoteString(con, file.path(directory, sprintf("part[%d].parquet", part)))
    sql <- sprintf(paste0(
      "COPY (SELECT i AS id, %d::INTEGER AS YEAR, md5(i::VARCHAR) AS tag ",
      "FROM range(%d, %d) AS t(i)) TO %s (FORMAT PARQUET, ROW_GROUP_SIZE 122880)"
    ), year, part * rows / 4, (part + 1L) * rows / 4, output)
    DBI::dbExecute(con, sql)
  }
}

run_sort <- function(path, spill, rows, threads, output, profile = NULL, cap = "768MB") {
  old <- options(easyNIS.duckdb_config = list(
    memory_limit = "192MB", max_temp_directory_size = cap,
    temp_directory = spill, threads = threads, preserve_insertion_order = FALSE
  ))
  on.exit(options(old))
  stopifnot(!length(list.files(spill, all.files = TRUE, no.. = TRUE)))
  query <- easyNIS::nis_open(path, check_release = FALSE)
  con <- dbplyr::remote_con(query)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  on.exit(unlink(output), add = TRUE)
  stopifnot(length(list.files(spill, all.files = TRUE, no.. = TRUE)) == 1L)
  source <- dbplyr::sql_render(dplyr::select(query, id, tag))
  target <- DBI::dbQuoteString(con, output)
  copy <- paste0("COPY (SELECT id, tag FROM (", source,
    ") AS input ORDER BY tag, id) TO ", target, " (FORMAT PARQUET)")

  if (!is.null(profile)) {
    profile_output <- tempfile("profile-", tmpdir = dirname(output), fileext = ".json")
    on.exit(unlink(profile_output), add = TRUE)
    DBI::dbExecute(con, "PRAGMA enable_profiling = 'json'")
    DBI::dbExecute(con, "SET profiling_coverage = 'ALL'")
    DBI::dbExecute(con, paste("SET profiling_output =", DBI::dbQuoteString(con, profile_output)))
  }
  start <- proc.time()[["elapsed"]]
  failure <- tryCatch({ DBI::dbExecute(con, copy); NULL }, error = identity)
  seconds <- proc.time()[["elapsed"]] - start
  if (!is.null(profile)) {
    # DuckDB can profile the disabling statement and overwrite the COPY metrics.
    if (is.null(failure)) stopifnot(file.copy(profile_output, profile))
    DBI::dbExecute(con, "PRAGMA disable_profiling")
  }
  bytes <- if (is.null(failure)) {
    check <- DBI::dbGetQuery(con, paste0(
      "SELECT count(*) AS n, sum(id) AS checksum, min(id) AS first_id, max(id) AS last_id ",
      "FROM read_parquet(", target, ")"
    ))
    stopifnot(check$n == rows, check$checksum == rows * (rows - 1) / 2,
      check$first_id == 0, check$last_id == rows - 1L)
    file.info(output)$size
  } else {
    NA_real_
  }
  rm(query)
  invisible(gc())
  stopifnot(!DBI::dbIsValid(con), dir.exists(spill),
    !length(list.files(spill, all.files = TRUE, no.. = TRUE)))
  if (!is.null(failure)) stop(failure)
  data.frame(threads, seconds, output_bytes = bytes)
}

profile_numbers <- function(path) {
  profile <- jsonlite::read_json(path)
  if (is.null(profile$system)) {
    query <- profile$query_name
    spill <- profile$system_peak_temp_dir_size
    buffer <- profile$system_peak_buffer_memory
  } else {
    query <- profile$query$sql
    spill <- profile$system$peak_temp_dir_size
    buffer <- profile$system$peak_buffer_memory
  }
  stopifnot(length(query) == 1L, startsWith(query, "COPY "))
  stopifnot(is.numeric(spill), spill > 0, spill <= 768e6, is.numeric(buffer), buffer > 0)
  c(buffer_mib = buffer / 1024^2, spill_mib = spill / 1024^2)
}

verify_spill <- function(scratch, evidence) {
  path <- file.path(scratch, "parquet")
  spill <- file.path(scratch, "spill")
  stopifnot(dir.create(path), dir.create(spill))
  rows <- 8000000L
  make_sort_fixture(path, rows)
  parts <- list.files(path, pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE)
  cat("FIXTURE ", rows, " rows, ", sum(file.info(parts)$size), " compressed bytes\n", sep = "")
  opts <- options(easyNIS.duckdb_config = list(threads = 1L, temp_directory = spill))
  on.exit(options(opts))
  selected <- easyNIS::nis_open(path, years = 2020L, check_release = FALSE)
  con <- dbplyr::remote_con(selected)
  sources <- getFromNamespace("nis_open_source_paths", "easyNIS")(selected)
  expected <- parts[basename(dirname(parts)) == "YEAR=2020"]
  stopifnot(identical(sort(sources), sort(expected)))
  count <- dplyr::count(selected, YEAR) |> dplyr::collect()
  stopifnot(identical(count$YEAR, 2020L), count$n == rows / 2L)
  rm(selected)
  invisible(gc())
  stopifnot(!DBI::dbIsValid(con), !length(list.files(spill, all.files = TRUE, no.. = TRUE)))
  cat("SELECTION PASS 2020 Hive parts only\n")
  output <- file.path(scratch, "sorted.parquet")
  configs <- c(1L, 2L)
  peaks <- vapply(configs, function(threads) {
    profile <- file.path(evidence, sprintf("sort-threads-%d.json", threads))
    run_sort(path, spill, rows, threads, output, profile)
    profile_numbers(profile)
  }, c(buffer_mib = 0, spill_mib = 0))
  colnames(peaks) <- as.character(configs)
  print(peaks)

  trials <- lapply(seq_len(5L), function(i) {
    order <- if (i %% 2L) configs else rev(configs)
    do.call(rbind, lapply(order, function(threads) {
      measurement <- run_sort(path, spill, rows, threads, output)
      data.frame(trial = i, measurement, rows_per_second = rows / measurement$seconds)
    }))
  })
  trials <- do.call(rbind, trials)
  utils::write.csv(trials, file.path(evidence, "timings.csv"), row.names = FALSE)
  write.csv(peaks, file.path(evidence, "peaks.csv"))
  print(trials)
  print(vapply(split(trials$seconds, trials$threads), function(times) {
    c(median = median(times), min = min(times), max = max(times))
  }, c(median = 0, min = 0, max = 0)))

  failure <- tryCatch(run_sort(path, spill, rows, 1L, output, cap = "1MB"), error = identity)
  stopifnot(inherits(failure, "error"),
    grepl("offload|temporary directory|max_temp_directory_size", conditionMessage(failure)),
    !file.exists(output), !length(list.files(spill, all.files = TRUE, no.. = TRUE)))
  cat("SPILL CAP PASS ", conditionMessage(failure), "\n", sep = "")
}

verification_run("duckdb-spill", verify_spill, packages = "jsonlite")
