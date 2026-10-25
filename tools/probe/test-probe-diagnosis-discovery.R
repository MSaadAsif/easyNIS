#!/usr/bin/env Rscript

source(file.path("tools", "probe", "diagnosis-discovery.R"))

testthat::test_that("lazy schema discovery preserves diagnosis and POA in a design", {
  data <- data.frame(
    YEAR = rep(2020L, 4L),
    HOSP_NIS = c(1L, 1L, 2L, 2L),
    NIS_STRATUM = c(1L, 1L, 2L, 2L),
    DISCWT = rep(1, 4L),
    AGE = c(64L, 70L, 55L, 80L),
    I10_DX1 = c("I210", "J189", "I500", "E119"),
    DXPOA1 = c("Y", "N", "U", "W"),
    check.names = FALSE
  )
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(connection, "probe_fixture", data)
  query <- dplyr::tbl(connection, "probe_fixture")

  fields <- probe_diagnosis_fields(query)

  testthat::expect_identical(fields, c("I10_DX1", "DXPOA1"))
  selected <- dplyr::collect(dplyr::select(query, dplyr::all_of(fields)))
  testthat::expect_identical(selected$I10_DX1, data$I10_DX1)
  testthat::expect_identical(selected$DXPOA1, data$DXPOA1)

  design <- easyNIS::nis_flag_dx(query, ami = "I21") |>
    easyNIS::nis_design(ami, keep = c(AGE, tidyselect::all_of(fields)))
  testthat::expect_true(all(fields %in% names(design$variables)))
  testthat::expect_identical(design$variables$I10_DX1, "I210")
  testthat::expect_identical(design$variables$DXPOA1, "Y")
})
