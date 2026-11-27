source("tools/probe/published-verification/estimands.R")

local({
  fixture <- tempfile("invented-published-estimates-")
  dir.create(fixture)
  on.exit(unlink(fixture, recursive = TRUE))
  options(easyNIS.duckdb_config = list(threads = 2L, memory_limit = "4GB"))
  inputs <- data.frame(
    YEAR = rep(2019:2022, each = 48L),
    HOSP_NIS = rep(rep(1:2, each = 24L), 4L),
    NIS_STRATUM = 1L,
    DISCWT = rep(c(2, 3), each = 24L, times = 4L),
    AGE = rep(c(17L, 18L), each = 24L, times = 4L),
    fixture_row = rep(seq_len(48L), 4L),
    I10_DX1 = "I501",
    I10_DX2 = rep(rep(c("U071", "J1282", "U099", "U0710"), each = 12L), 4L)
  )
  inputs$I10_DX1[inputs$I10_DX2 == "U071"] <- "U099"
  con <- DBI::dbConnect(duckdb::duckdb(), config = list(threads = "2", memory_limit = "4GB"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (year in 2019:2022) {
    DBI::dbWriteTable(con, "invented", inputs[inputs$YEAR == year, ], overwrite = TRUE)
    path <- file.path(fixture, paste0("NIS_", year, ".parquet"))
    DBI::dbExecute(con, paste("COPY invented TO", DBI::dbQuoteString(con, path), "(FORMAT PARQUET)"))
  }
  results <- withCallingHandlers(published_estimands(fixture), easynis_release_mismatch = function(w) {
    invokeRestart("muffleWarning")
  })
  print(results)
  stopifnot(identical(unname(vapply(results, `[[`, numeric(1), "estimate")), c(120, 72, 84)))
  too_small <- easyNIS::nis_open(fixture, years = 2022L, check_release = FALSE) |>
    dplyr::filter(fixture_row == 1L) |>
    dplyr::mutate(discharge = 1)
  small_error <- tryCatch(
    published_total(easyNIS::nis_design(too_small, cohort = TRUE, keep = discharge)),
    error = conditionMessage
  )
  stopifnot(identical(small_error, "The sample is below the HCUP disclosure threshold."))
})
