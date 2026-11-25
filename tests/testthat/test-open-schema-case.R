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

test_that("normalization collisions retain coalesced names and values", {
  path <- tempfile("nis-unicode-case-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  data <- data.frame(YEAR = 2019L, first = NA_integer_, second = 7L)
  names(data)[2:3] <- c("A\u00e9", "A\u00c9")
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))
  for (reader in c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")) {
    actual <- dplyr::collect(nis_open(path, reader = reader))
    expect_setequal(names(actual), c("YEAR", "A\u00c9"))
    expect_identical(actual[["A\u00c9"]], 7L)
  }
})

test_that("pooled normalization collisions coalesce after annual type promotion", {
  path <- tempfile("nis-pooled-unicode-case-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, first = 1L, second = 2L,
    check.names = FALSE)
  names(first)[2:3] <- c("A\u00e9", "A\u00c9")
  second <- data.frame(YEAR = 2020L, first = 20L, second = 10L,
    check.names = FALSE)
  names(second)[2:3] <- c("A\u00c9", "A\u00e9")
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  for (reader in readers) {
    actual <- nis_open(path, reader = reader) |>
      dplyr::arrange(YEAR) |>
      dplyr::collect()
    expect_identical(actual[["A\u00c9"]], c(1L, 10L))
  }
})

test_that("normalization collisions coalesce after character promotion", {
  path <- tempfile("nis-pooled-unicode-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, first = NA_integer_, second = "alpha",
    check.names = FALSE)
  names(first)[2:3] <- c("A\u00e9", "A\u00c9")
  second <- data.frame(YEAR = 2020L, first = "beta", second = "gamma",
    check.names = FALSE)
  names(second)[2:3] <- c("A\u00e9", "A\u00c9")
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  for (reader in readers) {
    actual <- nis_open(path, reader = reader) |>
      dplyr::arrange(YEAR) |>
      dplyr::collect()
    expect_identical(actual[["A\u00c9"]], c("alpha", "beta"))
  }
})

test_that("source spelling proposals do not merge existing normalized outputs", {
  path <- tempfile("nis-unicode-source-name-collision-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, value = 11L)
  names(first)[[2L]] <- "a\u00e9"
  second <- data.frame(YEAR = 2020L, mixed = 22L, uppercase = 29L,
    check.names = FALSE)
  names(second)[2:3] <- c("A\u00e9", "A\u00c9")
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  actual <- nis_open(path) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_setequal(names(actual), c("YEAR", "a\u00e9", "A\u00c9"))
  expect_identical(actual[["a\u00e9"]], c(11L, 22L))
  expect_identical(actual[["A\u00c9"]], c(NA_integer_, 29L))
})

test_that("source spelling proposals preserve promoted normalization values", {
  path <- tempfile("nis-unicode-source-name-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, value = 11L)
  names(first)[[2L]] <- "a\u00e9"
  second <- data.frame(YEAR = 2020L, value = 22L)
  names(second)[[2L]] <- "A\u00e9"
  third <- data.frame(YEAR = 2021L, value = "separate")
  names(third)[[2L]] <- "A\u00c9"
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))
  write_duckdb_parquet(third, file.path(path, "NIS_2021.parquet"))

  actual <- nis_open(path) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_setequal(names(actual), c("YEAR", "a\u00e9", "A\u00c9"))
  expect_identical(actual[["a\u00e9"]], c(11L, 22L, NA_integer_))
  expect_identical(actual[["A\u00c9"]], c(NA_character_, NA_character_,
    "separate"))
})

test_that("canonical rename proposals that share a target stay unchanged", {
  path <- tempfile("nis-shared-canonical-target-")
  dir.create(path)
  withr::defer(unlink(path, recursive = TRUE))
  first <- stats::setNames(data.frame(2019L, 1L, 2L), c("YEAR", "a\u00e9", "a\u00c9"))
  second <- stats::setNames(data.frame(2020L, 3L, 4L), c("YEAR", "A\u00e9", "A\u00c9"))
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  actual <- nis_open(path) |> dplyr::arrange(YEAR) |> dplyr::collect()
  expect_setequal(names(actual), c("YEAR", "a\u00e9", "a\u00c9"))
  expect_identical(actual[["a\u00e9"]], c(1L, 3L))
  expect_identical(actual[["a\u00c9"]], c(2L, 4L))
})

test_that("wide sources keep separate Unicode columns and values", {
  path <- tempfile("nis-unicode-wide-name-collisions-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  suffixes <- sprintf("%02d", seq_len(12L))
  lower_names <- paste0("a\u00e9_", suffixes)
  mixed_names <- paste0("A\u00e9_", suffixes)
  upper_names <- paste0("A\u00c9_", suffixes)
  first <- as.data.frame(matrix(as.integer(c(2019L, seq_len(24L))), nrow = 1L),
    check.names = FALSE)
  names(first) <- c("YEAR", lower_names, upper_names)
  second <- as.data.frame(matrix(as.integer(c(2020L, 100L + seq_len(24L))),
    nrow = 1L), check.names = FALSE)
  names(second) <- c("YEAR", mixed_names, upper_names)
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  actual <- nis_open(path) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()

  expect_setequal(names(actual), c("YEAR", lower_names, upper_names))
  expect_identical(unname(as.matrix(actual[lower_names])),
    rbind(as.integer(seq_len(12L)), as.integer(100L + seq_len(12L))))
  expect_identical(unname(as.matrix(actual[upper_names])),
    rbind(as.integer(12L + seq_len(12L)), as.integer(112L + seq_len(12L))))
})

test_that("lowercase Greek sigma spellings remain separate columns", {
  path <- tempfile("nis-lowercase-sigma-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  data <- data.frame(YEAR = 2019L, first = 1L, second = 2L)
  names(data)[2:3] <- c("\u03c3", "\u03c2")
  write_duckdb_parquet(data, file.path(path, "NIS_2019.parquet"))

  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  for (reader in readers) {
    actual <- dplyr::collect(nis_open(path, reader = reader))
    expect_identical(actual[["\u03c3"]], 1L)
    expect_identical(actual[["\u03c2"]], 2L)
  }
})

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

test_that("unrelated projections survive promoted Unicode normalization collisions", {
  path <- tempfile("nis-unicode-unrelated-projection-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, first = 1L, second = 2L, KEEP = 31L)
  names(first)[2:3] <- c("A\u00e9", "A\u00c9")
  second <- data.frame(YEAR = 2020L, value = "beta", KEEP = 32L)
  names(second)[2L] <- "A\u00c9"
  second[["__easynis_scan_alias_41c3a9"]] <- 999L
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  actual <- nis_open(path) |>
    dplyr::select(YEAR, KEEP) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_identical(actual$YEAR, c(2019L, 2020L))
  expect_identical(actual$KEEP, c(31L, 32L))
})

test_that("real alias-like fields remain independent of Unicode names", {
  path <- tempfile("nis-real-scan-alias-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  first <- data.frame(YEAR = 2019L, first = 1L, second = 2L, KEEP = 31L)
  names(first)[2:3] <- c("A\u00e9", "A\u00c9")
  second <- data.frame(YEAR = 2020L, KEEP = 32L)
  second[["__easynis_scan_alias_41c3a9"]] <- 999L
  write_duckdb_parquet(first, file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(second, file.path(path, "NIS_2020.parquet"))

  actual <- nis_open(path) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_identical(actual[["A\u00c9"]], c(1L, NA_integer_))
  expect_identical(actual[["__easynis_scan_alias_41c3a9"]],
    c(NA_integer_, 999L))
})
