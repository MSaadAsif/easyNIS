source("tools/experiments/in-database-survey/workload.R")
options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE,
  survey.multicore = FALSE, na.action = "na.omit")
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L, dir.exists(args))
out <- args[[1L]]
command <- paste("Rscript --vanilla tools/experiments/in-database-survey/verify.R",
  shQuote(out))

check_fixture <- function(seed) {
  set.seed(seed)
  years <- 2018:2020
  d <- do.call(rbind, lapply(years, function(year) {
    psus <- c(2L, sample(3:7, sample(2:4, 1), replace = TRUE))
    h <- rep(seq_len(sum(psus)), each = 40)
    age <- sample(18:95, length(h), replace = TRUE)
    female <- rbinom(length(h), 1, 0.5)
    los <- rpois(length(h), 2 + age / 40 + h / 25 + (year - 2018) / 3)
    died <- rbinom(length(h), 1, plogis(-3 + age / 45 + female / 3 + h / 50))
    female[h %% 3L == 2L] <- 0L
    # A PSU missing every LOS, some partially missing outcomes and a PSU with no
    # model-complete records. The first stratum has two PSUs and no domain rows
    # in 2018. In the other years, only one of the two PSUs can have members.
    los[h == 2L | runif(length(h)) < 0.08] <- NA
    died[h == 1L | runif(length(h)) < 0.04] <- NA
    age[runif(length(h)) < 0.04] <- NA
    female[h == 2L | (year == 2018 & h == 1L)] <- 0L
    if (year != 2018) {
      age[5L] <- 70L
      female[5L] <- 1L
      los[5L] <- 4L
    }
    w <- runif(length(h), 2, 9)
    w[1:3] <- c(NA, 0, Inf)
    data.frame(YEAR = year, HOSP_NIS = h,
      NIS_STRATUM = rep(seq_along(psus), psus)[h], DISCWT = w,
      AGE = age, FEMALE = female, LOS = los, DIED = died)
  }))
  valid <- Reduce(`&`, lapply(d[design_fields], function(x) is.finite(x) & x > 0))
  con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = "4")))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "fixture", d)
  paths <- vapply(years, function(y) {
    path <- tempfile(tmpdir = out, fileext = ".parquet")
    DBI::dbExecute(con, sprintf("COPY (SELECT * FROM fixture WHERE YEAR = %d)
      TO %s (FORMAT PARQUET)", y, DBI::dbQuoteString(con, path)))
    path
  }, character(1))
  on.exit(unlink(paths), add = TRUE)
  open_views(con, paths)
  query <- function(sql) DBI::dbGetQuery(con, sql)
  stopifnot(as.numeric(query("SELECT count(*) AS n FROM valid")$n) == sum(valid))
  reference <- reference_design(d[valid, ])
  cases <- c(names(workloads), names(fixture_cases))
  checks <- lapply(cases, function(call) {
    sql <- sql_call(query, call, years)
    ref <- reference_call(reference, call)
    scores <- differences(sql, ref)
    data.frame(seed = seed, call = call, t(scores), pass = all(scores <= 1e-8))
  })
  do.call(rbind, checks)
}

seeds <- 2601:2612
results <- do.call(rbind, lapply(seeds, check_fixture))
write.table(results, file.path(out, "agreement.tsv"), sep = "\t", row.names = FALSE,
  quote = FALSE)
versions <- vapply(c("DBI", "duckdb", "survey", "srvyr", "dplyr"), function(pkg) {
  paste0(pkg, ": ", packageVersion(pkg))
}, character(1))
writeLines(c(paste("Command:", command),
  paste("Platform:", R.version$platform), R.version.string, versions,
  paste("RNG:", paste(RNGkind(), collapse = ", ")),
  paste("Seeds:", paste(seeds, collapse = ", ")),
  paste("Cases:", nrow(results)), paste("Passed:", sum(results$pass))),
  file.path(out, "manifest.txt"))
stopifnot(all(results$pass))
