# Compare slot layouts with identical result fingerprints on the invented fixture.
args <- commandArgs(TRUE)
root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
threads <- args[[2]]
task <- args[[3]]
Sys.setenv(DUCKDB_THREADS = threads)
library(DBI)
con <- dbConnect(duckdb::duckdb(config = list(threads = threads, memory_limit = paste0(threads, "GB"))))
q <- function(x) as.character(dbQuoteString(con, x))
id <- function(x) as.character(dbQuoteIdentifier(con, x))
source <- paste0("read_parquet(", q(file.path(root, "invented", "*.parquet")), ")")
csv <- file.path(root, paste0("prototype-", task, "-", threads, ".csv"))
take <- function(expr) {
  t <- Sys.time()
  value <- force(expr)
  list(value = value, ms = 1000 * as.numeric(difftime(Sys.time(), t, units = "secs")))
}
frame <- function(name, build, prepare, eval, value, size = NA_real_) {
  data.frame(
    task,
    threads,
    variant = name,
    build_ms = build,
    prepare_ms = prepare,
    eval_ms = eval,
    bytes = size,
    value = paste(unlist(value, use.names = FALSE), collapse = " ")
  )
}
bench <- function(name, sql) {
  built <- take(force(sql))
  prepared <- take(dbExecute(con, paste("PREPARE measured AS", built$value)))
  result <- take(dbGetQuery(con, "EXECUTE measured"))
  dbExecute(con, "DEALLOCATE measured")
  frame(name, built$ms, prepared$ms, result$ms, result$value)
}
run_query <- function(sql) {
  paste(
    "SELECT count(*)::DOUBLE AS rows, sum(v::INTEGER)::DOUBLE AS matched,",
    "count(*) FILTER (WHERE v IS NULL)::DOUBLE AS unknown FROM (",
    sql,
    ")"
  )
}

if (task %in% c("flag", "ccsr", "comorbidity", "timing")) {
  is_pr <- task == "timing"
  n <- if (is_pr) 25L else 40L
  codes <- id(paste0(if (is_pr) "I10_PR" else "I10_DX", seq_len(n)))
  aux <- if (is_pr) {
    id(paste0("PRDAY", seq_len(n)))
  } else {
    ifelse(seq_len(n) <= 25L, id(paste0("DXPOA", seq_len(n))), "NULL::VARCHAR")
  }
  any_of <- function(x) paste0("(", paste(x, collapse = " OR "), ")")
  arr <- function(x) paste0("[", paste(x, collapse = ", "), "]")
  dx <- function(code, poa) {
    switch(
      task,
      flag = paste0("starts_with(", code, ", 'I50')"),
      ccsr = paste0(code, " IN ('I509', 'I2510')"),
      comorbidity = paste0("(", code, " IN ('I509', 'E119') AND ", poa, " = 'Y')")
    )
  }
  timing <- function(index, outcome, missing) {
    paste(
      "CASE WHEN",
      outcome,
      "THEN TRUE WHEN",
      index,
      "AND",
      missing,
      "THEN NULL ELSE FALSE END"
    )
  }
  wide <- function() {
    if (!is_pr) {
      expr <- paste0("coalesce(", any_of(dx(codes, aux)), ", false)")
      return(run_query(paste("SELECT", expr, "AS v FROM", source)))
    }
    day <- sprintf("CASE WHEN %s >= 0 THEN %s END", aux, aux)
    index <- sprintf("starts_with(%s, '0270')", codes)
    outcome <- sprintf("starts_with(%s, '02L73')", codes)
    minimum <- sprintf("least(%s)", paste(sprintf("CASE WHEN %s THEN %s END", index, day), collapse = ", "))
    match <- any_of(sprintf("(%s AND (%s - ix) BETWEEN 0 AND 3)", outcome, day))
    missing <- sprintf(
      "%s AND %s",
      any_of(outcome),
      any_of(sprintf("((%s OR %s) AND %s IS NULL)", index, outcome, day))
    )
    run_query(paste(
      "SELECT",
      timing(any_of(index), match, missing),
      "AS v FROM (SELECT *,",
      minimum,
      "AS ix FROM",
      source,
      ")"
    ))
  }
  lists <- function() {
    if (!is_pr) {
      expr <- if (task == "comorbidity") {
        sprintf(
          "list_reduce(list_transform(list_zip(%s, %s), x -> coalesce(%s, false)), (a,b) -> a OR b)",
          arr(codes),
          arr(aux),
          dx("x[1]", "x[2]")
        )
      } else {
        sprintf(
          "list_reduce(list_transform(%s, x -> coalesce(%s, false)), (a,b) -> a OR b)",
          arr(codes),
          dx("x", "NULL")
        )
      }
      return(run_query(paste("SELECT", expr, "AS v FROM", source)))
    }
    items <- sprintf("list_zip(%s, %s)", arr(codes), arr(aux))
    index <- "list_filter(items, x -> starts_with(x[1], '0270'))"
    outcome <- "list_filter(items, x -> starts_with(x[1], '02L73'))"
    match <- "length(list_filter(outs, x -> x[2] - ix BETWEEN 0 AND 3)) > 0"
    missing <- paste(
      "length(outs) > 0 AND",
      "length(list_filter(list_concat(inds, outs), x -> x[2] IS NULL OR x[2] < 0)) > 0"
    )
    run_query(paste(
      "SELECT",
      timing("length(inds) > 0", match, missing),
      "AS v",
      "FROM (SELECT inds, outs, list_min(list_transform(inds, x -> CASE WHEN x[2] >= 0 THEN x[2] END)) AS ix",
      "FROM (SELECT",
      index,
      "AS inds,",
      outcome,
      "AS outs FROM (SELECT",
      items,
      "AS items FROM",
      source,
      ")))"
    ))
  }
  unpivot <- function() {
    use_aux <- task %in% c("comorbidity", "timing")
    aliases <- id(paste0("aux", seq_len(n)))
    selected <- if (use_aux) paste(sprintf("%s AS %s", aux, aliases), collapse = ", ") else NULL
    slots <- if (use_aux) paste0("(", codes, ", ", aliases, ") AS s", seq_len(n)) else codes
    paste0(
      "SELECT YEAR, KEY_NIS, slot, code",
      if (use_aux) ", aux",
      " FROM (SELECT YEAR, KEY_NIS, ",
      paste(c(codes, selected), collapse = ", "),
      " FROM ",
      source,
      ") UNPIVOT INCLUDE NULLS (",
      if (use_aux) "(code, aux)" else "code",
      " FOR slot IN (",
      paste(slots, collapse = ", "),
      ")) WHERE code IS NOT NULL"
    )
  }
  long <- function(from) {
    if (!is_pr) {
      matched <- sprintf("SELECT YEAR, KEY_NIS, TRUE AS v FROM %s WHERE %s GROUP BY ALL", from, dx("code", "aux"))
      return(run_query(paste(
        "SELECT coalesce(m.v, false) AS v FROM",
        source,
        "LEFT JOIN (",
        matched,
        ") m USING (YEAR, KEY_NIS)"
      )))
    }
    match <- "coalesce(bool_or(outcome AND (aux - ix) BETWEEN 0 AND 3), false)"
    missing <- "bool_or(outcome) AND bool_or((idx OR outcome) AND (aux IS NULL OR aux < 0))"
    run_query(paste(
      "SELECT CASE WHEN m.present THEN m.v ELSE false END AS v FROM",
      source,
      "LEFT JOIN (SELECT YEAR, KEY_NIS, true AS present,",
      timing("bool_or(idx)", match, missing),
      "AS v FROM (SELECT *, min(CASE WHEN idx AND aux >= 0 THEN aux END)",
      "OVER (PARTITION BY YEAR, KEY_NIS) AS ix FROM (SELECT *, starts_with(code, '0270') AS idx,",
      "starts_with(code, '02L73') AS outcome FROM",
      from,
      ")) GROUP BY YEAR, KEY_NIS)",
      "m USING (YEAR, KEY_NIS)"
    ))
  }
  rows <- rbind(
    bench("wide", wide()),
    bench("lists", lists()),
    bench("unpivot_view", long(paste0("(", unpivot(), ")")))
  )
  stage <- take(dbExecute(con, paste("CREATE TEMP TABLE long_slots AS", unpivot())))
  temp <- bench("unpivot_table", long("long_slots"))
  stage_row <- frame("build_long_table", 0, 0, stage$ms, stage$value)
  write.csv(rbind(rows, temp, stage_row), csv, row.names = FALSE)
  stopifnot(length(unique(c(rows$value, temp$value))) == 1L)
} else if (task %in% c("layout", "settings")) {
  scan <- function(relation) {
    paste(
      "SELECT count(*) AS n, sum(LOS) AS los, count(I10_DX1) AS diagnoses FROM",
      relation,
      "WHERE YEAR = 2020 AND HOSP_NIS BETWEEN 41 AND 60"
    )
  }
  if (task == "layout") {
    src <- paste0("read_parquet(", q(file.path(root, "invented", "NIS_2020.parquet")), ")")
    rows <- list()
    dbExecute(con, "CREATE TYPE diagnosis_code AS ENUM ('I509','I2510','E119','J449','Z3800')")
    for (layout in c("source", "sorted", "sorted_enum")) {
      for (group in c(16384, 122880, 524288)) {
        variant <- paste(layout, group, sep = "_")
        path <- tempfile(tmpdir = root, fileext = ".parquet")
        src_sql <- paste(
          "SELECT",
          if (layout == "sorted_enum") "* REPLACE (I10_DX1::diagnosis_code AS I10_DX1)" else "*",
          "FROM",
          src,
          if (layout == "source") "" else "ORDER BY YEAR, HOSP_NIS, KEY_NIS"
        )
        write <- take(dbExecute(
          con,
          paste("COPY (", src_sql, ") TO", q(path), "(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE", group, ")")
        ))
        rel <- paste0("read_parquet(", q(path), ")")
        result <- bench(variant, scan(rel))
        eligible <- dbGetQuery(
          con,
          paste0(
            "SELECT count(*) AS groups, count(*) FILTER (WHERE ",
            "stats_min_value::INTEGER <= 60 AND stats_max_value::INTEGER >= 41) AS candidate_groups ",
            "FROM parquet_metadata(",
            q(path),
            ") WHERE path_in_schema = 'HOSP_NIS'"
          )
        )
        rows[[variant]] <- cbind(result, write_ms = write$ms, file_bytes = file.info(path)$size, eligible)
        unlink(path)
      }
    }
    result <- do.call(rbind, rows)
  } else {
    setting <- function(x, val) dbExecute(con, paste("SET", x, "=", val))
    combination <- list(
      base = c("true", "false", "false", "true"),
      no_order = c("false", "false", "false", "true"),
      object_cache = c("true", "true", "false", "true"),
      parquet_metadata = c("true", "false", "true", "true"),
      no_external_cache = c("true", "false", "false", "false")
    )
    keys <- c("preserve_insertion_order", "enable_object_cache", "parquet_metadata_cache", "enable_external_file_cache")
    result <- do.call(
      rbind,
      lapply(names(combination), function(key) {
        mapply(setting, keys, combination[[key]])
        rbind(bench(paste0(key, "_first"), scan(source)), bench(paste0(key, "_repeat"), scan(source)))
      })
    )
  }
  write.csv(result, csv, row.names = FALSE)
  stopifnot(length(unique(result$value)) == 1L)
} else {
  stop("Unknown task: ", task)
}
dbDisconnect(con, shutdown = TRUE)
