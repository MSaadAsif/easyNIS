args <- commandArgs(trailingOnly = TRUE)
mode <- args[[1L]]
run <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
threads <- as.integer(args[[3L]])
memory_mb <- as.integer(args[[4L]])
database <- file.path(run, "views.duckdb")
years <- 2018:2020
design_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
dx_fields <- paste0("I10_DX", 1:40)
adult <- "coalesce(AGE >= 65 AND FEMALE = 1, FALSE)"
model_complete <- "DIED IS NOT NULL AND AGE IS NOT NULL AND FEMALE IS NOT NULL"
valid <- paste(sprintf("coalesce(isfinite(%1$s) AND %1$s > 0, FALSE)",
  design_fields), collapse = " AND ")

config <- function(spill) {
  list(threads = as.character(threads), memory_limit = paste(memory_mb, "MB"),
    temp_directory = spill, preserve_insertion_order = "true")
}

invent_files <- function(con) {
  set.seed(26L)
  vapply(years, function(year) {
    n <- 12000L
    hospital <- rep(seq_len(60L), each = n / 60L)
    age <- sample(18:95, n, replace = TRUE)
    female <- rbinom(n, 1, 0.52)
    shift <- (year - min(years)) / 4
    data <- data.frame(
      YEAR = year, HOSP_NIS = hospital, NIS_STRATUM = 1L + hospital %% 6L,
      DISCWT = runif(n, 3, 7), AGE = age, FEMALE = female,
      LOS = rpois(n, 3 + age / 40 + hospital / 30 + shift),
      DIED = rbinom(n, 1, plogis(-4 + age / 50 + female / 3 + shift))
    )
    data$DISCWT[seq_len(24L)] <- NA_real_
    data$LOS[seq(100L, n, by = 100L)] <- NA_integer_
    data$AGE[seq(70L, n, by = 100L)] <- NA_integer_
    hit <- hospital %% 5L == 0L & runif(n) < 0.3
    for (slot in dx_fields) data[[slot]] <- rep("Z000", n)
    data$I10_DX1[hit & hospital %% 2L == 0L] <- "I509"
    data$I10_DX40[hit & hospital %% 2L == 1L] <- "I501"
    path <- file.path(run, paste0("invented-", year, ".parquet"))
    DBI::dbWriteTable(con, "fixture", data, temporary = TRUE, overwrite = TRUE)
    DBI::dbExecute(con, paste("COPY fixture TO", DBI::dbQuoteString(con, path),
      "(FORMAT PARQUET)"))
    path
  }, character(1))
}

prepare <- function(source) {
  spill <- file.path(run, "setup-spill")
  dir.create(spill)
  on.exit(unlink(spill, recursive = TRUE))
  con <- DBI::dbConnect(duckdb::duckdb(), database, config = config(spill))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE, after = FALSE)
  fixture <- identical(source, "invented")
  files <- if (fixture) invent_files(con) else {
    annual <- file.path(source, sprintf("NIS_%s.parquet", years))
    parts <- lapply(annual, list.files, pattern = "\\.parquet$", full.names = TRUE)
    stopifnot(all(lengths(parts) == 4L))
    normalizePath(unlist(parts), winslash = "/", mustWork = TRUE)
  }
  paths <- paste(DBI::dbQuoteString(con, files), collapse = ", ")
  hf <- paste0("coalesce(starts_with(", dx_fields, ", 'I50'), FALSE)",
    collapse = " OR ")
  DBI::dbExecute(con, sprintf(paste(
    "CREATE VIEW raw_input AS SELECT %s, AGE, FEMALE, LOS, DIED,",
    "(%s) AS HF, filename FROM read_parquet([%s], union_by_name = true,",
    "filename = true, hive_partitioning = false)"),
    paste(design_fields, collapse = ", "), hf, paths))
  DBI::dbExecute(con, paste(
    "CREATE VIEW input AS SELECT * EXCLUDE (filename) FROM raw_input"))
  DBI::dbExecute(con, paste(
    "CREATE VIEW survey_input AS SELECT *,",
    "(YEAR - 2018) * 1000000 + HOSP_NIS AS BENCH_PSU,",
    "(YEAR - 2018) * 1000000 + NIS_STRATUM AS BENCH_STRATUM",
    "FROM input WHERE", valid))

  audit <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*) AS input_n,",
    "count(*) FILTER (WHERE %1$s) AS valid_n,",
    "count(*) FILTER (WHERE %1$s AND (%2$s)) AS adult_n,",
    "count(*) FILTER (WHERE %1$s AND (%3$s)) AS glm_n,",
    "coalesce(bool_and(NOT coalesce(isfinite(YEAR) AND YEAR > 0, FALSE) OR",
    "YEAR = try_cast(regexp_extract(filename, '(?:NIS_|invented-)(2018|2019|2020)', 1)",
    "AS INTEGER)), FALSE) AS years_ok,",
    "coalesce(bool_and(HOSP_NIS < 1000000 AND NIS_STRATUM < 1000000)",
    "FILTER (WHERE %1$s), FALSE) AS keys_ok,",
    "coalesce(bool_and(DIED IS NULL OR DIED IN (0, 1))",
    "FILTER (WHERE %1$s), FALSE) AS died_ok FROM raw_input"),
    valid, adult, model_complete))
  minimum_rows <- if (fixture) 30000 else 20000000
  if (!isTRUE(audit$keys_ok && audit$years_ok && audit$died_ok) ||
    as.numeric(audit$valid_n) < minimum_rows) {
    stop("Input validation failed (annual coverage, design keys or outcome encoding).")
  }
  # A diagnosis decoding error must not block trials that project numeric fields.
  hf_audit <- tryCatch(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*) FILTER (WHERE HF) AS hf_n,",
    "count(*) FILTER (WHERE HF AND (%s)) AS hf_glm_n FROM survey_input"),
    model_complete)),
    error = function(e) {
      if (!grepl("Invalid string encoding", conditionMessage(e), fixed = TRUE)) stop(e)
      writeLines("Invalid UTF-8 in a diagnosis projection.", file.path(run, "hf-audit-error.txt"))
      data.frame(hf_n = NA_real_, hf_glm_n = NA_real_)
    })
  audit <- cbind(audit, hf_audit)
  counts <- c("input_n", "valid_n", "adult_n", "hf_n", "glm_n", "hf_glm_n")
  audit[counts] <- lapply(audit[counts], as.numeric)
  if (any(unlist(audit[counts]) <= 10, na.rm = TRUE)) {
    stop("Input has an undersized benchmark domain.")
  }
  excluded <- audit$input_n - audit$valid_n
  audit$excluded <- if (excluded == 0) "none" else if (excluded <= 10) "suppressed" else excluded
  if (identical(audit$excluded, "suppressed")) audit$input_n <- NA_real_
  write.table(audit, file.path(run, "input-audit.tsv"), sep = "\t", row.names = FALSE)
  packages <- c("easyNIS", "DBI", "duckdb", "survey", "srvyr", "gtsummary", "dplyr")
  versions <- vapply(packages, function(pkg) {
    if (!requireNamespace(pkg, quietly = TRUE)) return("unavailable")
    as.character(utils::packageVersion(pkg))
  }, character(1))
  writeLines(c(R.version.string, paste(names(versions), versions)),
    file.path(run, "versions.txt"))
}

check_settings <- function(con, spill, trial) {
  settings <- DBI::dbGetQuery(con, paste(
    "SELECT current_setting('threads') AS threads,",
    "current_setting('memory_limit') AS memory_limit,",
    "current_setting('temp_directory') AS temp_directory,",
    "current_setting('preserve_insertion_order') AS preserve_order"))
  write.table(settings, file.path(trial, "settings.tsv"), sep = "\t", row.names = FALSE)
  # DuckDB reports the decimal-byte MB request back at one decimal in MiB/GiB.
  limit <- strsplit(settings$memory_limit, " ", fixed = TRUE)[[1L]]
  bytes <- as.numeric(limit[[1L]]) * c(MiB = 1024^2, GiB = 1024^3)[limit[[2L]]]
  if (!isTRUE(settings$threads == threads && settings$preserve_order &&
    normalizePath(settings$temp_directory, winslash = "/") == spill &&
    abs(bytes / (memory_mb * 1e6) - 1) < 0.02)) {
    stop("Effective DuckDB configuration does not match the requested profile.")
  }
}

statistics <- function(fit) {
  est <- stats::coef(fit)
  term <- if (inherits(fit, "svyby")) fit$YEAR else names(est)
  data.frame(term = term, estimate = unname(est),
    se = unname(survey::SE(fit)))
}

measure <- function(backend, task, trial, cache) {
  audit <- read.delim(file.path(run, "input-audit.tsv"))
  trial <- normalizePath(trial, winslash = "/")
  spill <- file.path(trial, "spill")
  dir.create(spill)
  options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE,
    survey.multicore = FALSE, na.action = "na.omit")
  loadNamespace("easyNIS")
  loadNamespace("duckdb") # DBI::dbDriver("duckdb") looks up the loaded namespace.
  stopifnot(identical(normalizePath(dirname(find.package("easyNIS")), winslash = "/"),
    file.path(run, "library")))
  con <- NULL
  on.exit(if (!is.null(con) && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
  keep <- switch(task, mean = "LOS", total = "DIED", by = "LOS",
    adult_mean = "LOS", adult_by = "LOS", hf_mean = "LOS",
    hf_glm = c("DIED", "AGE", "FEMALE"), glm = c("DIED", "AGE", "FEMALE"),
    srvyr = "LOS", table = "LOS")
  age_domain <- task %in% c("adult_mean", "adult_by", "srvyr")
  hf_domain <- startsWith(task, "hf_")
  start <- proc.time()[["elapsed"]]
  if (mode == "load") {
    loadNamespace("survey") # Register subset.DBIsvydesign in this interpreter.
    design <- readRDS(cache)
    con <- DBI::dbConnect(duckdb::duckdb(), database, read_only = TRUE, config = config(spill))
    if (backend == "dbi") design$db$connection <- con
  } else if (backend == "dbi") {
    design <- survey::svydesign(ids = ~BENCH_PSU, strata = ~BENCH_STRATUM,
      weights = ~DISCWT, nest = TRUE, data = "survey_input", dbtype = "duckdb",
      dbname = database, read_only = TRUE, config = config(spill))
    con <- design$db$connection
  } else {
    con <- DBI::dbConnect(duckdb::duckdb(), database, read_only = TRUE, config = config(spill))
    data <- dplyr::tbl(con, "input")
    # Copy coded binaries under unlabeled source names, then retain numeric aliases.
    # nis_design otherwise turns DIED and FEMALE into factors for display.
    if ("DIED" %in% keep) {
      data <- dplyr::mutate(data, BENCH_DIED = DIED, BENCH_FEMALE = FEMALE)
      keep <- stats::setNames(keep, keep)
      numeric_fields <- intersect(keep, c("DIED", "FEMALE"))
      keep[numeric_fields] <- paste0("BENCH_", numeric_fields)
    }
    cohort <- if (age_domain) rlang::expr(dplyr::coalesce(AGE >= 65 & FEMALE == 1, FALSE)) else
      if (hf_domain) rlang::expr(HF) else TRUE
    # Design messages may contain licensed counts, including small cells.
    design <- suppressMessages(suppressWarnings(
      rlang::inject(easyNIS::nis_design(data, cohort = !!cohort, keep = keep))
    ))
  }
  build <- proc.time()[["elapsed"]] - start
  check_settings(con, spill, trial)
  expected <- if (age_domain) audit$adult_n else if (hf_domain) audit$hf_n else audit$valid_n
  stopifnot(NROW(design$cluster) == if (backend == "dbi") audit$valid_n else expected)
  writeLines(as.character(build), file.path(trial, "build-seconds.txt"))
  for (i in seq_len(200L)) {
    if (file.exists(file.path(trial, "build-sampled"))) break
    Sys.sleep(0.05)
  }
  if (mode == "build") {
    if (backend == "dbi") design$db$connection <- NULL
    saveRDS(design, cache, compress = FALSE)
    return(invisible(NULL))
  }

  start <- proc.time()[["elapsed"]]
  if (backend == "dbi" && age_domain && task != "srvyr") {
    design <- suppressWarnings(subset(design, AGE >= 65 & FEMALE == 1))
  }
  if (backend == "dbi" && hf_domain) design <- suppressWarnings(subset(design, HF))
  if (task %in% c("hf_glm", "glm")) {
    fit <- survey::svyglm(DIED ~ AGE + FEMALE + factor(YEAR), design,
      family = stats::quasibinomial(), rescale = FALSE,
      control = stats::glm.control(epsilon = 1e-10))
    stopifnot(fit$converged, fit$rank == 5L,
      stats::nobs(fit) == if (hf_domain) audit$hf_glm_n else audit$glm_n)
    result <- statistics(fit)
  } else if (task == "srvyr") {
    design <- srvyr::as_survey(design)
    if (backend == "dbi") design <- dplyr::filter(design, AGE >= 65 & FEMALE == 1)
    out <- design |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(LOS = srvyr::survey_mean(LOS, na.rm = TRUE))
    result <- data.frame(term = out$YEAR, estimate = out$LOS, se = out$LOS_se)
  } else if (task == "table") {
    tbl <- gtsummary::tbl_svysummary(design, include = "LOS", type = LOS ~ "continuous")
    stopifnot(inherits(tbl, "tbl_svysummary"))
    result <- NULL
  } else {
    fit <- switch(task,
      mean = , adult_mean = , hf_mean = survey::svymean(~LOS, design, na.rm = TRUE),
      total = survey::svytotal(~DIED, design, na.rm = TRUE),
      by = , adult_by = survey::svyby(~LOS, ~YEAR, design, survey::svymean, na.rm = TRUE))
    result <- statistics(fit)
  }
  call_seconds <- proc.time()[["elapsed"]] - start
  writeLines(as.character(call_seconds), file.path(trial, "call-seconds.txt"))
  if (backend == "dbi" && task %in% c("adult_mean", "adult_by", "hf_mean", "hf_glm")) {
    # DBIsvydesign represents a subset by zero weights while retaining all rows.
    stopifnot(sum(is.finite(design$prob)) == expected)
  }
  if (!is.null(result)) {
    stopifnot(all(is.finite(result$estimate)), all(is.finite(result$se)))
    if (task %in% c("by", "adult_by", "srvyr")) stopifnot(setequal(result$term, years))
    saveRDS(result, file.path(trial, "statistics.rds"))
  }
}

if (mode == "prepare") {
  prepare(args[[5L]])
} else {
  trial <- args[[7L]]
  writeLines(as.character(Sys.getpid()), file.path(trial, "pid"))
  status <- tryCatch({
    cache <- if (length(args) >= 8L) args[[8L]]
    measure(args[[5L]], args[[6L]], trial, cache)
    "ok"
  }, error = function(e) {
    message <- conditionMessage(e)
    if (grepl("Invalid string encoding", message, fixed = TRUE)) {
      message <- "DuckDB rejected invalid UTF-8 while projecting the diagnosis fields."
    }
    writeLines(message, file.path(trial, "error.txt"))
    "error"
  })
  writeLines(status, file.path(trial, "done"))
  # Let the external monitor read the kernel peak while the process still exists.
  for (i in seq_len(200L)) {
    if (file.exists(file.path(trial, "sampled"))) break
    Sys.sleep(0.05)
  }
  quit(status = as.integer(status != "ok"))
}
