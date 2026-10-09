# Invented reproduction of recovery through two declared margins.
# Run with source(system.file("examples/disclosure-subtotals.R", package = "easyNIS")).
library(easyNIS)
(function() {
  n <- 200L
  core <- nis_synthetic_data()$core[rep(1L, n), ]
  core$KEY_NIS <- sprintf("%06d", seq_len(n))
  core$HOSP_NIS <- sprintf("%04d", (seq_len(n) - 1L) %% 10L + 1L)
  core$NIS_STRATUM <- ifelse(core$HOSP_NIS <= "0005", 1L, 2L)
  core$DISCWT <- 5
  at <- function(index) as.integer(seq_len(n) %in% index)
  core$all <- 1L
  core$a <- at(1:3)
  core$b <- at(4:7)
  core$c <- at(8:37)
  core$d <- at(38:67)
  core$s <- core$c + core$d
  core$e <- 1L - core$a - core$b - core$s
  # If all, s and e were shown, all - s - e would expose seven discharges.
  stopifnot(sum(core$all - core$s - core$e) == 7,
    sum(core$DISCWT * (core$all - core$s - core$e)) == 35)
  session <- nis_open()
  path <- tempfile(fileext = ".parquet")
  on.exit({ nis_close(session); unlink(path) })
  DBI::dbWriteTable(session$connection, "invented_subtotals", core)
  DBI::dbExecute(session$connection, paste0("COPY invented_subtotals TO ",
    DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
  fields <- c("all", "a", "b", "c", "d", "s", "e")
  design <- nis_survey_design(nis_import(session, path, 2022), fields, TRUE,
    "hospital_wr", "fail")
  spec <- data.frame(id = fields, field = fields, statistic = "total",
    label = paste("Invented", fields), unit = "weighted discharges")
  table <- nis_descriptive_table(design, spec, "fail", 8, 0.95, "wr_unadjusted")
  nis_disclosure_review(table, c(1, 10), "display", 2,
    list(list(total = "all", parts = c("a", "b", "c", "d", "e")),
      list(total = "s", parts = c("c", "d"))))
})()
