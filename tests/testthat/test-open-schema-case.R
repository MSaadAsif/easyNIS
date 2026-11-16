schema_case_fixture <- function(spellings) {
  path <- tempfile("nis-schema-case-")
  dir.create(path)
  for (index in seq_along(spellings)) {
    data <- data.frame(YEAR = 2018L + index, value = index,
      analyst_note = paste0("note-", index), check.names = FALSE)
    names(data)[[2L]] <- spellings[[index]]
    data[['analyst"tag']] <- paste0("tag-", index)
    data$APRDRG_RISK_MORTALITY_1 <- 10L + index
    write_duckdb_parquet(data, # nolint: object_usage_linter
      file.path(path, paste0("NIS_", 2018L + index, ".parquet")))
  }
  path
}

test_that("single sources retain the established case normalization", {
  spellings <- c("aprdrg_risk_mortality", "APRDRG_Risk_Mortality",
    "APRDRG_RISK_MORTALITY")
  path <- schema_case_fixture(spellings)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  for (index in seq_along(spellings)) {
    query <- nis_open(path, years = 2018L + index)
    field <- if (index == 1L) spellings[[index]] else toupper(spellings[[index]])
    expect_s3_class(query, "tbl_sql")
    expect_setequal(colnames(query), c("YEAR", field, "analyst_note",
      'analyst"tag', "APRDRG_RISK_MORTALITY_1"))
    actual <- dplyr::collect(dplyr::select(query, dplyr::all_of(field)))
    expect_identical(actual[[field]], index)
  }
})

test_that("pooled canonical recognition is independent of source order", {
  for (spellings in list(c("aprdrg_risk_mortality", "APRDRG_Risk_Mortality"),
    c("APRDRG_Risk_Mortality", "aprdrg_risk_mortality"))) {
    path <- schema_case_fixture(spellings)
    withr::defer(unlink(path, recursive = TRUE))
    query <- nis_open(path)
    expect_s3_class(query, "tbl_sql")
    expect_setequal(colnames(query), c("YEAR", "APRDRG_RISK_MORTALITY",
      "analyst_note", 'analyst"tag', "APRDRG_RISK_MORTALITY_1"))
    actual <- query |>
      dplyr::select(YEAR, APRDRG_RISK_MORTALITY, analyst_note,
        dplyr::all_of('analyst"tag'), APRDRG_RISK_MORTALITY_1) |>
      dplyr::arrange(YEAR) |>
      dplyr::collect()
    expect_identical(actual$APRDRG_RISK_MORTALITY, 1:2)
    expect_identical(actual$APRDRG_RISK_MORTALITY_1, 11:12)
    expect_identical(actual$analyst_note, c("note-1", "note-2"))
    expect_identical(actual[['analyst"tag']], c("tag-1", "tag-2"))

    sources <- list.files(path, full.names = TRUE)
    con <- nis_duckdb_connect()
    reversed <- nis_duckdb_query_from_parquet(con, rev(sources)) |>
      nis_open_normalize_names() |>
      dplyr::select(dplyr::all_of(names(actual))) |>
      dplyr::arrange(YEAR) |>
      dplyr::collect()
    DBI::dbDisconnect(con, shutdown = TRUE)
    expect_identical(reversed, actual)
  }
})

test_that("lowercase-only pooled fields keep their spelling and projection", {
  path <- schema_case_fixture(rep("aprdrg_risk_mortality", 2L))
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  query <- nis_open(path)
  expect_true("aprdrg_risk_mortality" %in% colnames(query))
  expect_false("APRDRG_RISK_MORTALITY" %in% colnames(query))
  actual <- query |>
    dplyr::select(YEAR, aprdrg_risk_mortality) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_identical(actual$aprdrg_risk_mortality, 1:2)
})

test_that("case normalization preserves DuckDB-disambiguated source columns", {
  path <- tempfile("nis-schema-collision-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  con <- nis_duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  destination <- DBI::dbQuoteString(con, file.path(path, "NIS_2019.parquet"))
  DBI::dbExecute(con, paste0("COPY (SELECT 2019 AS YEAR, ",
    "1 AS aprdrg_risk_mortality, 9 AS APRDRG_Risk_Mortality) TO ",
    destination, " (FORMAT PARQUET)"))
  actual <- dplyr::collect(nis_open(path))
  expect_setequal(names(actual), c("YEAR", "aprdrg_risk_mortality",
    "APRDRG_RISK_MORTALITY_1"))
  expect_identical(actual$aprdrg_risk_mortality, 1L)
  expect_identical(actual$APRDRG_RISK_MORTALITY_1, 9L)
})

test_that("Arrow scans share pooled canonical recognition", {
  skip_if_not_installed("arrow")
  path <- schema_case_fixture(c("aprdrg_risk_mortality", "APRDRG_Risk_Mortality"))
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  actual <- nis_open(path, reader = "arrow") |>
    dplyr::select(YEAR, APRDRG_RISK_MORTALITY) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_identical(actual$APRDRG_RISK_MORTALITY, 1:2)
})
