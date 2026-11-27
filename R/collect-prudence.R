#' @exportS3Method dbplyr::db_collect
db_collect.nis_duckdb_connection <- function(con, sql, n = -1, warn_incomplete = TRUE, ...) {
  nis_collect_check(con, sql, n)
  NextMethod()
}

nis_collect_available <- function() {
  tryCatch(ps::ps_system_memory()$avail, error = function(error) NA_real_)
}

nis_collect_check <- function(con, sql, n = -1) {
  if (identical(getOption("easyNIS.collect_prudence"), FALSE) || isTRUE(n == 0)) {
    return(invisible(NULL))
  }
  available <- nis_collect_available()
  if (!isTRUE(is.finite(available) & available > 0)) {
    cli::cli_inform(
      "Could not detect available system memory. Continuing without the easyNIS collect check.",
      .frequency = "once",
      .frequency_id = "easyNIS_collect_memory_unavailable"
    )
    return(invisible(NULL))
  }
  estimate <- tryCatch(nis_collect_estimate(con, sql, n), error = function(error) NULL)
  if (is.null(estimate)) {
    return(invisible(NULL))
  }
  bytes <- estimate$rows * estimate$row_width
  if (bytes >= available * 0.5) {
    rows <- nis_collect_count(con, sql, n)
    bytes <- rows * estimate$row_width
  }
  if (!is.finite(bytes) || bytes < available * 0.2) {
    return(invisible(NULL))
  }

  # Leave at least half of available RAM for DuckDB's result, temporary copies
  # during conversion to R, and allocations made after collect(). At a fifth
  # of available RAM there is still room to proceed, but users should know the cost.
  if (bytes >= available * 0.5) {
    cli::cli_abort(
      c(
        "Collect would use too much available memory.",
        i = paste(
          "Use {.fn dplyr::filter} or {.fn dplyr::select} before collecting.",
          "For survey analysis, use {.fn nis_design} with a narrower cohort and fewer retained columns."
        ),
        i = "To proceed anyway, set {.code options(easyNIS.collect_prudence = FALSE)}."
      ),
      class = "easyNIS_collect_too_large"
    )
  }
  cli::cli_inform("Collecting a large result from DuckDB.")
  invisible(NULL)
}

nis_collect_estimate <- function(con, sql, n) {
  # DuckDB discovers dynamic PIVOT columns by executing its input at bind time.
  if (grepl("\\bpivot\\b", sql, ignore.case = TRUE, perl = TRUE)) {
    return(NULL)
  }
  # Keep the usual path cheap. An exact count can rerun a join, filter or
  # aggregation over every row, so only pay for it before a possible abort.
  plans <- DBI::dbGetQuery(con, paste("EXPLAIN (FORMAT JSON)", sql))
  physical <- plans$explain_value[plans$explain_key == "physical_plan"]
  plan <- jsonlite::fromJSON(physical, simplifyVector = FALSE)[[1L]]
  # The physical plan omits the limit on STREAMING_LIMIT. dbplyr renders
  # head() and collect(n = ...) as a trailing literal LIMIT.
  limit <- regmatches(sql, regexec("\\nLIMIT ([0-9]+)\\s*$", sql, perl = TRUE))[[1L]]
  rows <- min(nis_collect_plan_rows(plan), as.numeric(limit[-1L]), if (n >= 0) n else Inf, na.rm = TRUE)
  if (!is.finite(rows) || rows == 0) {
    return(NULL)
  }
  schema <- DBI::dbGetQuery(con, paste("DESCRIBE", sql))
  widths <- nis_collect_widths(con, sql, plan, schema)
  list(rows = rows, row_width = sum(widths))
}

nis_collect_count <- function(con, sql, n) {
  tryCatch(
    {
      query <- paste0("SELECT COUNT(*) AS n FROM (", sql, ") AS collect_result")
      rows <- as.numeric(DBI::dbGetQuery(con, query)$n)
      if (n >= 0) min(rows, n) else rows
    },
    error = function(error) NA_real_
  )
}

nis_collect_plan_rows <- function(plan) {
  count <- as.numeric(plan$extra_info$"Estimated Cardinality")
  if (isTRUE(is.finite(count) & count > 0)) {
    return(count)
  }
  switch(
    plan$name,
    EMPTY_RESULT = 0,
    UNGROUPED_AGGREGATE = 1,
    PROJECTION = nis_collect_plan_rows(plan$children[[1L]]),
    ORDER_BY = nis_collect_plan_rows(plan$children[[1L]]),
    STREAMING_LIMIT = nis_collect_plan_rows(plan$children[[1L]]),
    TOP_N = min(nis_collect_plan_rows(plan$children[[1L]]), as.numeric(plan$extra_info$Top), Inf, na.rm = TRUE),
    HASH_JOIN = {
      # DuckDB can implement LIMIT as a semi-join on row IDs. In this plan
      # a missing join estimate still allows us to bound its left input.
      if (!identical(plan$extra_info$"Join Type", "SEMI")) {
        return(NA_real_)
      }
      nis_collect_plan_rows(plan$children[[1L]])
    },
    UNION = sum(vapply(plan$children, nis_collect_plan_rows, numeric(1))),
    NA_real_
  )
}

nis_collect_widths <- function(con, sql, plan, schema) {
  types <- schema$column_type
  text <- types == "VARCHAR"
  fixed <- grepl(
    "^(BOOLEAN|U?(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT)|FLOAT|DOUBLE|DATE|TIME(STAMP.*)?|INTERVAL)$",
    types
  ) |
    startsWith(types, "DECIMAL(")
  # Fresh Windows collects from invented Parquet files peaked at about 13
  # bytes per numeric cell, 25 per repeated ICD-like cell and 102 per unique
  # short string, including DuckDB's result. Use the repeated-string budget
  # for known code slots when sampling a derived query would rerun its work.
  code <- grepl("^(I10_)?(DX|PR|DXPOA)[0-9]+$", schema$column_name, ignore.case = TRUE)
  widths <- ifelse(fixed, 16, ifelse(text & code, 32, 112))
  original <- identical(as.character(sql), attr(con, "easyNIS_collect")$source)
  unfiltered_scan <- identical(plan$name, "READ_PARQUET") && is.null(plan$extra_info$Filters)
  if (any(text) && (original || unfiltered_scan)) {
    widths[text] <- nis_collect_text_widths(con, sql, schema$column_name[text])
  }
  widths
}

nis_collect_text_widths <- function(con, sql, names) {
  # Even a LIMIT can rerun a whole filtered or grouped query. The caller
  # restricts this sample to source reads.
  columns <- DBI::dbQuoteIdentifier(con, names)
  stats <- c(
    paste0("COALESCE(MAX(strlen(", columns, ")), 0)"),
    paste0("COUNT(DISTINCT ", columns, ") / NULLIF(COUNT(*), 0)")
  )
  sample <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT ",
      paste(stats, collapse = ", "),
      " FROM (SELECT * FROM (",
      sql,
      ") AS source LIMIT 2048) AS sample"
    )
  )
  values <- vapply(sample, as.numeric, numeric(1))
  bytes <- values[seq_along(names)]
  distinct <- values[length(names) + seq_along(names)]
  # R interns distinct strings. DuckDB and R also allocate payload beyond
  # DuckDB's inline string capacity. The long-text fixture peaked at 366
  # bytes/cell with 129-byte unique strings, including conversion overhead.
  32 + 80 * ifelse(is.na(distinct), 1, distinct) + 2.5 * pmax(bytes - 12, 0)
}
