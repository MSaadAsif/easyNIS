# Single-category CCSR presence at the same scope as the wide baseline.
args <- commandArgs(TRUE)
root <- args[[1]]
p <- args[[2]]
Sys.setenv(DUCKDB_THREADS = p)
library(DBI)
con <- dbConnect(duckdb::duckdb(config = list(threads = p, memory_limit = paste0(p, "GB"))))
q <- function(x) as.character(dbQuoteString(con, x))
slots <- paste(dbQuoteIdentifier(con, paste0("I10_DX", 1:40)), collapse = ", ")
input <- paste0("read_parquet(", q(file.path(root, "invented", "*.parquet")), ")")
mapping <- paste0("read_parquet(", q(normalizePath("inst/ccsr/map.parquet", winslash = "/")), ")")
t <- Sys.time()
sql <- paste(
  "WITH matches AS (SELECT list(DISTINCT code) AS codes FROM",
  mapping,
  "WHERE type = 'dx' AND version = '2025.1' AND category = 'CIR019')",
  "SELECT count(*)::DOUBLE AS rows, sum(coalesce(list_has_any([",
  slots,
  "], codes), false)::INTEGER)::DOUBLE AS matched FROM",
  input,
  "CROSS JOIN matches"
)
build <- Sys.time()
dbExecute(con, paste("PREPARE category_presence AS", sql))
prepared <- Sys.time()
result <- dbGetQuery(con, "EXECUTE category_presence")
finished <- Sys.time()
elapsed <- function(a, b) 1000 * as.numeric(difftime(a, b, units = "secs"))
write.csv(
  cbind(
    result,
    build_ms = elapsed(build, t),
    prepare_ms = elapsed(prepared, build),
    eval_ms = elapsed(finished, prepared)
  ),
  file.path(root, paste0("ccsr-presence-", p, ".csv")),
  row.names = FALSE
)
stopifnot(result$rows == 2500000, result$matched >= 0L, result$matched <= result$rows)
dbDisconnect(con, shutdown = TRUE)
