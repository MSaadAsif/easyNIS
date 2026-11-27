# Explicit owner-only input. Read footer metadata and schema, never record values.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
paths <- list.files(args[[1]], pattern = "^NIS_[0-9]{4}[.]parquet$", full.names = TRUE)
stopifnot(length(paths) > 0L)
con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = "2", memory_limit = "2GB")))
lit <- paste(DBI::dbQuoteString(con, paths), collapse = ", ")
file_arg <- paste0("[", lit, "]")
metadata <- paste0("parquet_metadata(", file_arg, ")")
schema <- paste0("parquet_schema(", file_arg, ")")
groups <- DBI::dbGetQuery(
  con,
  paste(
    "WITH groups AS (SELECT DISTINCT file_name, row_group_id, row_group_num_rows, row_group_bytes",
    "FROM",
    metadata,
    ") SELECT regexp_extract(file_name, 'NIS_([0-9]{4})', 1) AS year,",
    "count(*) AS row_groups, min(row_group_num_rows) AS min_group_rows,",
    "median(row_group_num_rows) AS median_group_rows, max(row_group_num_rows) AS max_group_rows,",
    "min(row_group_bytes) AS min_group_bytes, median(row_group_bytes) AS median_group_bytes,",
    "max(row_group_bytes) AS max_group_bytes FROM groups GROUP BY year ORDER BY year"
  )
)
# Count whether statistics exist without retrieving their record-derived values.
columns <- DBI::dbGetQuery(
  con,
  paste(
    "SELECT path_in_schema AS field, type, compression, encodings, count(*) AS chunks,",
    "count(stats_min_value) AS chunks_with_min, count(stats_max_value) AS chunks_with_max,",
    "count(stats_null_count) AS chunks_with_null_count,",
    "count(stats_distinct_count) AS chunks_with_distinct_count FROM",
    metadata,
    "GROUP BY ALL ORDER BY field, type, encodings"
  )
)
types <- DBI::dbGetQuery(
  con,
  paste(
    "SELECT name, type, repetition_type, converted_type, logical_type, count(*) AS footer_entries",
    "FROM",
    schema,
    "GROUP BY ALL ORDER BY name, type"
  )
)
pruning <- DBI::dbGetQuery(
  con,
  paste(
    "WITH ranges AS (SELECT file_name, row_group_id, upper(path_in_schema) AS field,",
    "try_cast(stats_min_value AS DOUBLE) AS lo, try_cast(stats_max_value AS DOUBLE) AS hi",
    "FROM",
    metadata,
    "WHERE upper(path_in_schema) IN ('YEAR', 'HOSP_NIS')),",
    "adjacent AS (SELECT *, lag(lo) OVER w AS prior_lo, lag(hi) OVER w AS prior_hi FROM ranges",
    "WINDOW w AS (PARTITION BY file_name, field ORDER BY row_group_id))",
    "SELECT regexp_extract(file_name, 'NIS_([0-9]{4})', 1) AS year, field,",
    "count(*) FILTER (WHERE lo = hi) AS constant_groups,",
    "count(*) FILTER (WHERE prior_hi IS NOT NULL AND lo IS NOT NULL) AS comparable_neighbors,",
    "count(*) FILTER (WHERE prior_hi >= lo AND prior_lo <= hi) AS overlapping_neighbors",
    "FROM adjacent GROUP BY ALL ORDER BY year, field"
  )
)
path <- file.path(args[[2]], "private")
dir.create(path, showWarnings = FALSE)
write.csv(groups, file.path(path, "row-groups.csv"), row.names = FALSE)
write.csv(columns, file.path(path, "column-statistic-availability.csv"), row.names = FALSE)
write.csv(types, file.path(path, "schema.csv"), row.names = FALSE)
write.csv(pruning, file.path(path, "key-range-overlap.csv"), row.names = FALSE)
DBI::dbDisconnect(con, shutdown = TRUE)
