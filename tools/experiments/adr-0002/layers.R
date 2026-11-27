# Measure connection dispatch and collection preflight with identical results.
args <- commandArgs(TRUE)
root <- args[[1]]
p <- args[[2]]
Sys.setenv(DUCKDB_THREADS = p)
options(easyNIS.duckdb_config = list(threads = p, memory_limit = paste0(p, "GB")))
pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)
library(DBI)
library(dplyr)
measure <- function(fn) {
  start <- Sys.time()
  result <- fn()
  list(ms = 1000 * as.numeric(difftime(Sys.time(), start, units = "secs")), result = result)
}
con <- dbConnect(duckdb::duckdb(config = list(threads = p, memory_limit = paste0(p, "GB"))))
wrapped <- methods::new("nis_duckdb_connection", con)
rows <- list()
for (i in 1:5) {
  for (kind in if (i %% 2L) c("plain", "subclass") else c("subclass", "plain")) {
    db <- if (kind == "plain") con else wrapped
    trial <- measure(function() replicate(100, dbGetQuery(db, "SELECT 1 AS value")$value))
    stopifnot(all(trial$result == 1L))
    rows[[length(rows) + 1L]] <- data.frame(i, kind, ms = trial$ms / 100)
  }
}
dbDisconnect(con, shutdown = TRUE)
input <- nis_open(file.path(root, "invented"), check_release = FALSE)
query <- input |> filter(AGE >= 40L) |> select(YEAR, I10_DX1)
sql <- dbplyr::sql_render(query)
con <- dbplyr::remote_con(query)
stopifnot(easyNIS:::nis_collect_count(con, sql, -1) == 1812500)
initial <- NULL
for (i in 1:5) {
  for (kind in if (i %% 2L) c("guarded", "unguarded", "count") else c("count", "unguarded", "guarded")) {
    options(easyNIS.collect_prudence = kind == "guarded")
    trial <- measure(
      if (kind == "count") {
        function() easyNIS:::nis_collect_count(con, sql, -1)
      } else {
        function() collect(query)
      }
    )
    if (kind != "count") {
      stopifnot(nrow(trial$result) == 1812500)
      if (is.null(initial)) {
        initial <- trial$result
      }
      stopifnot(identical(trial$result, initial))
    }
    rows[[length(rows) + 1L]] <- data.frame(i, kind, ms = trial$ms)
  }
}
write.csv(do.call(rbind, rows), file.path(root, paste0("layers-", p, ".csv")), row.names = FALSE)
