#!/usr/bin/env Rscript

source(".agents/skills/verify/runner.R")

year_domain <- function(type, valid, invalid = character(), hive_range = character(),
                        missing = NA_character_) {
  value <- c(missing, valid, invalid, hive_range)
  annual <- c(rep(NA_character_, length(missing)), valid,
    rep("range", length(invalid) + length(hive_range)))
  hive <- rep("partition", length(value))
  hive[is.na(value) | value == "2020"] <- "2020"
  if (type == "DOUBLE") hive[value %in% "NaN"] <- "2020"
  hive[!is.na(value) & value %in% hive_range] <- "range"
  data.frame(type, value, annual, hive, stringsAsFactors = FALSE)
}

year_domains <- function() {
  list(
    year_domain("INTEGER", c("-2147483648", "2019", "2020", "2147483647")),
    year_domain("BIGINT", c("-2147483648", "2019", "2020", "2147483647"),
      c("-9223372036854775808", "-2147483649", "2147483648", "9223372036854775807")),
    year_domain("UBIGINT", c("0", "2019", "2020", "2147483647"),
      c("2147483648", "18446744073709551615")),
    year_domain("DOUBLE", c("-2147483648", "2019", "2020", "2147483647"),
      c("-Infinity", "Infinity", "2020.25", "2147483648"), missing = c(NA, "NaN")),
    year_domain("DECIMAL(16,4)", c("2019", "2020", "2147483647"),
      c("-2147483649", "2020.25", "2147483648")),
    year_domain("VARCHAR", c("2019", "2020", "2147483647"),
      c("bad", "2147483648"), hive_range = "2020.25", missing = c(NA, "NaN")),
    year_domain("", character())
  )
}

write_year_parts <- function(con, domain, root) {
  paths <- matrix("", nrow(domain), 2L)
  for (side in seq_len(ncol(paths))) {
    for (i in seq_len(nrow(domain))) {
      path <- file.path(root, sprintf("part[%d]-%02d.parquet", side, i))
      value <- domain$value[[i]]
      literal <- if (is.na(value)) "NULL" else DBI::dbQuoteString(con, value)
      type <- domain$type[[i]]
      year <- if (nzchar(type)) sprintf(", CAST(%s AS %s) AS YEar", literal, type) else ""
      sql <- sprintf("COPY (SELECT %d AS id%s) TO %s (FORMAT PARQUET)",
        side, year, DBI::dbQuoteString(con, path))
      DBI::dbExecute(con, sql)
      paths[i, side] <- path
    }
  }
  paths
}

expected_scan <- function(domain, selected, hive) {
  year <- if (hive) domain$hive[selected] else domain$annual[selected]
  if (hive && "partition" %in% year) {
    return(list(status = "partition", files = match("partition", year)))
  }
  invalid <- which(year == "range")
  if (length(invalid)) return(list(status = "range", files = invalid))
  if (!hive && !nzchar(domain$type[[1L]])) year <- NULL
  list(status = "accepted", ids = 1:2, year = year)
}

observed_scan <- function(plan, con, parts) {
  tryCatch({
    query <- plan(parts, con, "duckdb")$query
    sql <- dbplyr::sql_render(query)
    year <- if ("YEAR" %in% colnames(query)) ', CAST("YEAR" AS VARCHAR) AS year' else ""
    rows <- DBI::dbGetQuery(con, paste0(
      "SELECT id", year, " FROM (", sql, ") AS planned ORDER BY id"
    ))
    list(status = "accepted", ids = rows$id, year = rows$year)
  }, error = function(condition) {
    detail <- conditionMessage(condition)
    status <- if (grepl("conflict with Hive partition", detail, fixed = TRUE)) {
      "partition"
    } else if (grepl("Invalid `YEAR` values", detail, fixed = TRUE)) {
      "range"
    } else {
      "unexpected"
    }
    files <- unname(which(vapply(basename(parts$path), grepl, logical(1), x = detail, fixed = TRUE)))
    result <- list(status = status, files = files)
    if (status == "unexpected") result$detail <- detail
    result
  })
}

check_scans <- function(scratch, evidence) {
  plan <- getFromNamespace("nis_open_plan_parquet", "easyNIS")
  con <- DBI::dbConnect(duckdb::duckdb(config = list(threads = "1")))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  domains <- year_domains()
  dput(domains, file = file.path(evidence, "domains.R"))
  checked <- 0L
  for (i in seq_along(domains)) {
    domain <- domains[[i]]
    directory <- file.path(scratch, paste0("type-", i))
    stopifnot(dir.create(directory))
    paths <- write_year_parts(con, domain, directory)
    for (hive in c(FALSE, TRUE)) {
      for (left in seq_len(nrow(domain))) {
        for (right in seq_len(nrow(domain))) {
          selected <- c(left, right)
          parts <- data.frame(path = paths[cbind(selected, 1:2)],
            partition_year = if (hive) 2020L else NA_integer_)
          expected <- expected_scan(domain, selected, hive)
          actual <- observed_scan(plan, con, parts)
          if (!identical(expected, actual)) {
            witness <- list(type = domain$type[[1L]], values = domain$value[selected],
              hive = hive, expected = expected, actual = actual)
            dput(witness, file = file.path(evidence, "counterexample.R"))
            print(witness)
            stop("DuckDB scan counterexample. Read counterexample.R.")
          }
          checked <- checked + 1L
        }
      }
    }
  }
  cat("EXHAUSTIVE PASS ", checked, " ordered Parquet part pairs\n", sep = "")
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Pass at most one scratch package source path.")
verification_run("duckdb-parquet-scans", check_scans,
  source_dir = if (length(args)) args[[1L]] else ".")
