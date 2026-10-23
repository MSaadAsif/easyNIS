#!/usr/bin/env Rscript

source(file.path("tools", "probe", "diagnosis-discovery.R"))

data <- data.frame(
  AGE = 64L,
  I10_DX1 = "I210",
  DXPOA1 = "Y",
  check.names = FALSE
)
connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
tryCatch({
DBI::dbWriteTable(connection, "probe_fixture", data)
query <- dplyr::tbl(connection, "probe_fixture")

legacy_fields <- grep("^(?:I10_DX|DXPOA)[0-9]+$", names(query),
  value = TRUE, perl = TRUE)
fields <- probe_diagnosis_fields(query)

stopifnot(!length(legacy_fields))
stopifnot(identical(fields, c("I10_DX1", "DXPOA1")))
stopifnot(identical(dplyr::collect(dplyr::select(query, dplyr::all_of(fields)))$I10_DX1,
  "I210"))
stopifnot(identical(dplyr::collect(dplyr::select(query, dplyr::all_of(fields)))$DXPOA1,
  "Y"))
}, finally = DBI::dbDisconnect(connection, shutdown = TRUE))
