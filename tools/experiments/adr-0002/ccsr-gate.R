# Run after capture.R <evidence> ccsr-fixture 2.
ccsr_gate <- function(root) {
  options(easyNIS.duckdb_config = list(threads = "2", memory_limit = "2GB"))
  pkgload::load_all(".", quiet = TRUE, export_all = FALSE, helpers = FALSE)
  input <- easyNIS::nis_open(file.path(root, "invented"), check_release = FALSE)
  con <- dbplyr::remote_con(input)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  # CIR019 matches I509, which the gate fixture removes from every fourth row.
  i <- 0:49999
  expected <- 5L *
    sum(Reduce(
      `|`,
      lapply(seq_len(40L), function(slot) {
        i %% 4L != 0L & (slot == 1L | (i + slot) %% 13L < 3L) & (i + slot) %% 5L == 0L
      })
    ))
  stopifnot(expected > 0L, expected < 250000L)
  results <- lapply(seq_len(3L), function(run) {
    start <- proc.time()[["elapsed"]]
    query <- easyNIS::nis_add_ccsr(input, categories = "CIR019")
    sql <- paste(
      "SELECT count(*)::DOUBLE AS rows,",
      "sum((len(ccsr) > 0)::INTEGER)::DOUBLE AS matched FROM (",
      dbplyr::sql_render(query),
      ") n"
    )
    before_prepare <- proc.time()[["elapsed"]]
    DBI::dbExecute(con, paste("PREPARE ccsr_gate AS", sql))
    prepared <- proc.time()[["elapsed"]]
    result <- DBI::dbGetQuery(con, "EXECUTE ccsr_gate")
    finished <- proc.time()[["elapsed"]]
    DBI::dbExecute(con, "DEALLOCATE ccsr_gate")
    stopifnot(result$rows == 250000L, result$matched == expected)
    c(run = run, prepare = prepared - before_prepare, execute = finished - prepared, total = finished - start)
  })
  times <- do.call(rbind, results)
  print(times)
  cat("Verified rows:", 250000L, "matched:", expected, "\n")
  medians <- apply(times[, -1L], 2L, stats::median)
  budget <- c(prepare = 0.75, execute = 12, total = 18)
  if (any(medians > budget)) {
    stop("CCSR seconds exceeded budget: ", paste(names(budget)[medians > budget], collapse = ", "))
  }
}

ccsr_gate(commandArgs(TRUE)[[1L]])
