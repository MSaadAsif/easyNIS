# Generate invented Parquet, then measure one entry point per R process.
args <- commandArgs(TRUE)
root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
task <- args[[2]]
threads <- if (length(args) > 2L) args[[3]] else "4"
memory <- paste0(threads, "GB")
Sys.setenv(DUCKDB_THREADS = threads)
options(easyNIS.duckdb_config = list(threads = threads, memory_limit = memory))
library(DBI)
library(duckdb)
library(dplyr)
fixture <- file.path(root, "invented")
q <- function(x) as.character(dbQuoteString(con, x))
ident <- function(x) as.character(dbQuoteIdentifier(con, x))
now <- function() as.numeric(Sys.time())
connect <- function() dbConnect(duckdb(config = list(threads = threads, memory_limit = memory)))

if (task == "fixture") {
  dir.create(fixture, showWarnings = FALSE)
  con <- connect()
  dx <- sprintf(
    "CASE WHEN (i + %1$d) %% 13 < 3 OR %1$d = 1 THEN CASE (i + %1$d) %% 5 WHEN 0 THEN 'I509' WHEN 1 THEN 'I2510' WHEN 2 THEN 'E119' WHEN 3 THEN 'J449' ELSE 'Z3800' END END AS I10_DX%1$d",
    1:40
  )
  pr <- sprintf(
    "CASE WHEN (i + %1$d) %% 19 < 3 OR %1$d = 1 THEN CASE WHEN (i + %1$d) %% 2 = 0 THEN '02703ZZ' ELSE '02L73DK' END END AS I10_PR%1$d",
    1:25
  )
  day <- sprintf("CASE WHEN (i + %1$d) %% 31 <> 0 THEN ((i + %1$d) %% 9)::INTEGER END AS PRDAY%1$d", 1:25)
  poa <- sprintf("CASE WHEN (i + %1$d) %% 11 < 8 THEN 'Y' ELSE 'N' END AS DXPOA%1$d", 1:25)
  extra <- sprintf("hash(i + %1$d) %% 1000000 AS FIELD%1$d", 1:10)
  for (year in 2017:2021) {
    cols <- c(
      paste0(year, "::INTEGER AS YEAR"),
      "i::INTEGER AS KEY_NIS",
      "(i % 1000 + 1)::INTEGER AS HOSP_NIS",
      "(i % 20 + 1)::INTEGER AS NIS_STRATUM",
      "5 + (i % 11) / 20.0 AS DISCWT",
      "(1 + i % 4)::INTEGER AS DQTR",
      "(18 + i % 80)::INTEGER AS AGE",
      "(i % 89 = 0)::INTEGER AS DIED",
      "(1 + i % 13)::INTEGER AS LOS",
      "(1 + i % 5)::INTEGER AS DISPUNIFORM",
      "(i % 3)::INTEGER AS ELECTIVE",
      "(1000 + i % 8343)::INTEGER AS TOTCHG",
      "10::INTEGER AS DXVER",
      "10::INTEGER AS PRVER",
      dx,
      pr,
      day,
      poa,
      extra
    )
    stopifnot(length(cols) >= 129L)
    path <- q(file.path(fixture, sprintf("NIS_%d.parquet", year)))
    dbExecute(
      con,
      paste(
        "COPY (SELECT",
        paste(cols, collapse = ","),
        "FROM range(500000) AS input(i)) TO",
        path,
        "(FORMAT PARQUET, COMPRESSION ZSTD)"
      )
    )
  }
  # Conversion consumes one annual source. Write the invented input outside timing.
  input <- dbGetQuery(con, paste("FROM read_parquet(", q(file.path(fixture, "NIS_2020.parquet")), ")"))
  input[] <- lapply(input, function(x) if (inherits(x, "integer64")) as.double(x) else x)
  haven::write_sav(input, file.path(root, "NIS_2020.sav"))
  dbDisconnect(con, shutdown = TRUE)
  quit()
}

pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)
ens <- asNamespace("easyNIS")
dns <- asNamespace("duckdb")
out <- file.path(root, paste(task, threads, sep = "-"))
dir.create(out, showWarnings = FALSE)
profile <- normalizePath(file.path(out, "current.json"), winslash = "/", mustWork = FALSE)
mode <- if (length(args) > 3L) args[[4]] else "baseline"

call_label <- function() {
  paste(
    vapply(
      sys.calls(),
      function(x) {
        paste(deparse(x[[1]], nlines = 1L), collapse = "")
      },
      ""
    ),
    collapse = ";"
  )
}
wrap <- function(ns, name, replacement) {
  old <- get(name, ns)
  unlockBinding(name, ns)
  assign(name, replacement(old), ns)
  lockBinding(name, ns)
}

# Keep timers at the R/C boundary. Execution includes driver materialization.
events <- list()
connections <- list()
record <- function(part, start, sql = "", bytes = NA_real_) {
  elapsed <- 1000 * (now() - start)
  events[[length(events) + 1L]] <<- list(part = part, ms = elapsed, sql = sql, bytes = bytes, stack = call_label())
}
active <- FALSE
suppress_capture <- FALSE
logged <- function(con, i) {
  if (!dbIsValid(con)) {
    return()
  }
  suppress_capture <<- TRUE
  on.exit({
    suppress_capture <<- FALSE
  })
  logs <- dbGetQuery(con, "SELECT * FROM duckdb_logs() WHERE type = 'QueryLog' ORDER BY timestamp, context_id")
  write.csv(logs, file.path(out, sprintf("duckdb-log-%02d.csv", i)), row.names = FALSE)
}
wrap(ens, "nis_duckdb_connect", function(old) {
  function(config = list()) {
    start <- now()
    con <- old(config)
    if (active) {
      record("connect", start)
    }
    if (!active) {
      return(con)
    }
    suppress_capture <<- TRUE
    on.exit({
      suppress_capture <<- FALSE
    })
    connections[[length(connections) + 1L]] <<- con
    dbExecute(con, "CALL enable_logging('QueryLog', storage='memory')")
    dbExecute(con, "PRAGMA enable_profiling='json'")
    dbExecute(con, paste("SET profiling_output =", dbQuoteString(con, profile)))
    dbExecute(con, "SET profiling_coverage = 'ALL'")
    con
  }
})
wrap(dns, "rethrow_rapi_disconnect", function(old) {
  function(conn, ...) {
    for (i in seq_along(connections)) {
      if (identical(conn, connections[[i]]@conn_ref)) logged(connections[[i]], i)
    }
    start <- now()
    result <- old(conn, ...)
    if (active) {
      record("disconnect", start)
    }
    result
  }
})
wrap(dns, "rethrow_rapi_prepare", function(old) {
  function(conn, query, env, ...) {
    start <- now()
    result <- old(conn, query, env, ...)
    if (active && !suppress_capture) {
      record("prepare", start, query)
    }
    result
  }
})
wrap(dns, "duckdb_execute", function(old) {
  function(res) {
    capture <- active && !suppress_capture
    if (capture && file.exists(profile)) {
      unlink(profile)
    }
    start <- now()
    result <- old(res)
    if (capture) {
      record("execute", start, res@stmt_lst$str)
      if (file.exists(profile)) file.rename(profile, file.path(out, sprintf("query-%04d.json", length(events))))
    }
    result
  }
})
# The S3 rendering generic recurses. Count only the outer call.
render_depth <- 0L
wrap(asNamespace("dbplyr"), "sql_render", function(old) {
  function(...) {
    render_depth <<- render_depth + 1L
    on.exit({
      render_depth <<- render_depth - 1L
    })
    start <- now()
    result <- old(...)
    if (active && render_depth == 1L) {
      record("render", start)
    }
    result
  }
})
for (fn in c(
  "nis_collect_check",
  "nis_open_check_release",
  "nis_cohort_check_count",
  "nis_design_build",
  "nis_open_discover",
  "nis_open_normalize_names",
  "nis_duckdb_attach_finalizer",
  "nis_convert_validate_batch",
  "nis_convert_copy_batch",
  "nis_convert_haven_reader",
  "nis_design_cohort_type",
  "nis_design_fields",
  "nis_cmrb_validate_keys",
  "nis_validate_hospital_types"
)) {
  wrap(
    ens,
    fn,
    local({
      label <- fn
      function(old) {
        function(...) {
          start <- now()
          result <- old(...)
          if (active) {
            record(label, start)
          }
          result
        }
      }
    })
  )
}
wrap(dns, "duckdb_post_execute", function(old) {
  function(res, out) {
    start <- now()
    result <- old(res, out)
    if (active && !suppress_capture) {
      record("post-execute", start, res@stmt_lst$str, as.numeric(object.size(res@env$resultset)))
    }
    result
  }
})

input <- if (task %in% c("open", "open_skip", "open_arrow", "convert")) {
  NULL
} else {
  suppressWarnings(nis_open(fixture, check_release = FALSE))
}
if (task == "saved_design") {
  path <- tempfile(tmpdir = out)
  nis_write_cohort(input, KEY_NIS %% 200L == 0L, path, keep = c(AGE, LOS))
  input <- nis_open(path)
}
if (task == "suppress") {
  input <- nis_cell_counts(input, by = DQTR)
}
if (inherits(input, "tbl_sql")) {
  con <- dbplyr::remote_con(input)
  connections[[1]] <- con
  dbExecute(con, "CALL enable_logging('QueryLog', storage='memory')")
  dbExecute(con, "PRAGMA enable_profiling='json'")
  dbExecute(con, paste("SET profiling_output =", dbQuoteString(con, profile)))
  dbExecute(con, "SET profiling_coverage = 'ALL'")
}
force_flag <- function(data, column) {
  data |>
    summarise(matched = sum(as.integer(.data[[column]]), na.rm = TRUE), rows = n()) |>
    collect()
}
run <- switch(
  task,
  open = function() nis_open(fixture),
  open_skip = function() nis_open(fixture, check_release = FALSE),
  open_arrow = function() nis_open(fixture, reader = "arrow"),
  flag_dx = function() force_flag(nis_flag_dx(input, matched = "I50"), "matched"),
  flag_pr = function() force_flag(nis_flag_pr(input, matched = list(regex = "02L73[A-Z0-9]{2}")), "matched"),
  timing = function() {
    force_flag(
      nis_flag_pr_timing(input, "0270", "02L73", relation = "within_days", window = 3L, missing_day = "indeterminate"),
      "outcome_post_index"
    )
  },
  ccsr = function() {
    nis_add_ccsr(input, categories = "CIR019") |>
      summarise(matched = sum(as.integer(dbplyr::sql("len(ccsr) > 0")), na.rm = TRUE), rows = n()) |>
      collect()
  },
  ccsr_default = function() {
    force_flag(
      nis_add_ccsr(input, position = "default") |>
        mutate(matched = !is.na(ccsr)),
      "matched"
    )
  },
  ccsr_codes = function() nis_ccsr_codes("CIR019"),
  outcomes = function() {
    nis_outcomes(input) |>
      summarise(
        matched = sum(as.integer(in_hospital_death), na.rm = TRUE),
        days = sum(los_days, na.rm = TRUE),
        kinds = n_distinct(discharge_disposition),
        rows = n()
      ) |>
      collect()
  },
  comorbidity = function() force_flag(nis_comorbidity(input), "cmrb_hf"),
  attrition = function() nis_attrition(input, adult = AGE >= 40L, short = LOS < 4L, by_year = TRUE),
  design = function() nis_design(input, KEY_NIS %% 200L == 0L, keep = c(AGE, LOS, I10_DX1)),
  saved_design = function() nis_design(input, keep = c(AGE, LOS)),
  survey = function() survey::svymean(~LOS, subset(nis_survey(input), AGE >= 40)),
  survey_by = function() survey::svyby(~LOS, ~DQTR, subset(nis_survey(input), AGE >= 40), survey::svymean),
  survey_glm = function() survey::svyglm(DIED ~ AGE + LOS, nis_survey(input), family = quasibinomial()),
  annual = function() nis_annual_totals(input, AGE >= 40L),
  cells = function() nis_cell_counts(input, by = DQTR),
  suppress = function() nis_suppress(input, count_col = n, hospital_col = hospitals, by = DQTR),
  write = function() {
    nis_write_cohort(input, KEY_NIS %% 200L == 0L, tempfile(tmpdir = out), keep = c(AGE, LOS, I10_DX1))
  },
  convert = function() {
    destination <- tempfile(tmpdir = out)
    dir.create(destination)
    nis_convert(file.path(root, "NIS_2020.sav"), destination)
  },
  prday = function() nis_audit_prday(input, "02L73"),
  dx_audit = function() nis_audit_dx_position(input, "I50"),
  inventory = function() nis_audit_code_transition(input, c(hf = "I50"), type = "dx", output = "inventory"),
  audit = function() nis_audit_code_transition(input, c(hf = "I50"), type = "dx"),
  compute = function() dplyr::compute(select(input, YEAR, HOSP_NIS, LOS)),
  collect_narrow = function() collect(select(input, YEAR, HOSP_NIS, I10_DX1)),
  stop("unknown task: ", task)
)

invisible(gc())
warnings <- character()
Rprof(file.path(out, "Rprof.out"), interval = 0.05, event = "elapsed")
start <- now()
active <- TRUE
result <- tryCatch(
  withCallingHandlers(run(), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }),
  error = identity
)
ms <- 1000 * (now() - start)
active <- FALSE
Rprof(NULL)
for (i in seq_along(connections)) {
  logged(connections[[i]], i)
}
if (inherits(result, "tbl_sql")) {
  stopifnot(ncol(result) >= 3L)
} else if (!inherits(result, "error") && !is.null(result)) {
  capture.output(str(result, max.level = 1L), file = file.path(out, "result.txt"))
  if (is.data.frame(result) && nrow(result) <= 50L && ncol(result) <= 30L && !any(vapply(result, is.list, FALSE))) {
    write.csv(result, file.path(out, "result.csv"), row.names = FALSE)
  }
}
if (is.data.frame(result) && "rows" %in% names(result)) {
  stopifnot(as.numeric(result$rows) == 2500000)
}
writeLines(warnings, file.path(out, "warnings.txt"))
status <- if (inherits(result, "error")) conditionMessage(result) else "ok"
summary <- data.frame(
  task,
  threads,
  mode,
  ms,
  status,
  result_bytes = if (!inherits(result, "tbl_sql")) {
    as.numeric(object.size(result))
  } else {
    NA_real_
  }
)
write.csv(summary, file.path(out, "summary.csv"), row.names = FALSE)
if (length(events)) {
  write.csv(do.call(rbind, lapply(events, as.data.frame)), file.path(out, "events.csv"), row.names = FALSE)
}
raw <- readLines(file.path(out, "Rprof.out"), n = 200000L)[-1L]
stacks <- regmatches(raw, gregexpr('"[^"]+"', raw))
folded <- vapply(stacks, function(x) paste(rev(gsub('"', "", x, fixed = TRUE)), collapse = ";"), "")
weights <- table(folded[nzchar(folded)])
writeLines(paste(names(weights), as.integer(weights)), file.path(out, "flamegraph.folded"))
print(summary)
if (status != "ok") {
  quit(status = 1L)
}
