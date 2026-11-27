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
  if (is.null(estimate) || estimate$bytes < available * 0.2) {
    return(invisible(NULL))
  }

  # Leave at least half of available RAM for DuckDB's result, temporary copies
  # during conversion to R, and allocations made after collect(). At a fifth
  # of available RAM there is still room to proceed, but users should know the cost.
  gib <- 1024^3
  size <- format(round(estimate$bytes / 1024^2, 1), nsmall = 1, trim = TRUE)
  memory <- format(round(available / gib, 2), nsmall = 2, trim = TRUE)
  if (estimate$bytes >= available * 0.5) {
    cli::cli_abort(
      c(
        "Collect would use an estimated {size} MiB for {estimate$columns} column{?s} with {memory} GiB of available RAM.",
        i = paste(
          "Use {.fn dplyr::filter} or {.fn dplyr::select} before collecting.",
          "For survey analysis, use {.fn nis_design} with a narrower cohort and fewer retained columns."
        ),
        i = "To proceed anyway, set {.code options(easyNIS.collect_prudence = FALSE)}."
      ),
      class = "easyNIS_collect_too_large"
    )
  }
  cli::cli_inform(
    "Collecting {estimate$columns} column{?s} from DuckDB (estimated {size} MiB; {memory} GiB of RAM available)."
  )
  invisible(NULL)
}

nis_collect_estimate <- function(con, sql, n) {
  # An exact count could rerun a join, filter or aggregation over every row.
  # EXPLAIN binds the query and reads planner statistics without executing it.
  plans <- DBI::dbGetQuery(con, paste("EXPLAIN (FORMAT JSON)", sql))
  physical <- plans$explain_value[plans$explain_key == "physical_plan"]
  plan <- jsonlite::fromJSON(physical, simplifyVector = FALSE)[[1L]]
  rows <- nis_collect_plan_rows(plan)
  if (n >= 0) {
    rows <- min(rows, n, na.rm = TRUE)
  }
  if (!is.finite(rows) || rows == 0) {
    return(NULL)
  }
  schema <- DBI::dbGetQuery(con, paste("DESCRIBE", sql))
  widths <- nis_collect_widths(con, sql, plan, schema)
  list(bytes = rows * sum(widths), columns = length(widths))
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
  # Budget for R vectors and unshared string headers, even for short ICD codes.
  widths <- ifelse(fixed, 8, 128)
  original <- inherits(con, "nis_duckdb_connection") &&
    identical(as.character(sql), con@collect_source)
  unfiltered_scan <- identical(plan$name, "READ_PARQUET") && is.null(plan$extra_info$Filters)
  if (any(text) && (original || unfiltered_scan)) {
    # Only sample unfiltered source reads. Even a LIMIT can rerun the whole
    # query if it contains selective filters, sorting, windows, or grouping.
    columns <- DBI::dbQuoteIdentifier(con, schema$column_name[text])
    sample <- DBI::dbGetQuery(
      con,
      paste0(
        "SELECT ",
        paste0("MAX(strlen(", columns, "))", collapse = ", "),
        " FROM (SELECT * FROM (",
        sql,
        ") AS source LIMIT 32) AS sample"
      )
    )
    widths[text] <- pmax(widths[text], vapply(sample, as.numeric, numeric(1)) + 64, na.rm = TRUE)
  }
  widths
}
