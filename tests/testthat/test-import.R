test_that("sessions close idempotently without affecting another session", {
  first <- nis_open()
  second <- nis_open()
  on.exit(nis_close(first))
  on.exit(nis_close(second), add = TRUE)
  expect_true(DBI::dbIsValid(first$connection))
  nis_close(first)
  expect_true(first$closed)
  expect_silent(nis_close(first))
  expect_equal(DBI::dbGetQuery(second$connection, "SELECT 1 AS one")$one, 1L)
  expect_error(nis_import(first, "absent.parquet", 2022), "closed")
  expect_error(nis_close(list()), "nis_open")
})

test_that("local parquet import preserves codes and large string keys for every fixture year", {
  session <- nis_open()
  on.exit(nis_close(session))
  for (year in 2017:2022) {
    fixture <- nis_synthetic_data(year)
    path <- write_invented_parquet(session, fixture$core)
    on.exit(unlink(path), add = TRUE)
    data <- nis_import(session, path, year)
    collected <- nis_collect(data, names(fixture$core))
    expect_identical(collected, fixture$core)
    expect_equal(nrow(nis_collect(data, "KEY_NIS", limit = 3)), 3L)
    expect_equal(nrow(nis_collect(data, "KEY_NIS", limit = 0)), 0L)
    report <- nis_validate(data)
    expect_false(report$structural_errors)
    expect_false(report$analysis_ready)
    expect_true(all(report$issues$severity == "warning"))
    expect_identical(report$components$state, c("supplied", rep("not_supplied", 3L)))
  }
})

test_that("components join without multiplying rows or replacing shared fields", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()
  paths <- lapply(fixture[c("core", "hospital", "severity", "diagnosis_procedure_groups")],
                  function(data) write_invented_parquet(session, data))
  on.exit(unlink(unlist(paths)), add = TRUE)
  data <- nis_import(session, paths$core, 2022, hospital = paths$hospital,
    severity = paths$severity, diagnosis_procedure_groups = paths$diagnosis_procedure_groups)
  result <- nis_collect(data, c("KEY_NIS", "DISCWT", "NIS_STRATUM", "HOSP_BEDSIZE", "SYN_SEVERITY"))
  expect_equal(nrow(result), 12L)
  expect_equal(sum(result$DISCWT), 36)
  expect_equal(result$HOSP_BEDSIZE, rep(c(1L, 2L, 1L, 3L), each = 3L))
  expect_identical(data$joins$hospital$shared_columns, "NIS_STRATUM")
  expect_equal(data$joins$hospital$unmatched_core, 0)
  expect_false(nis_validate(data)$structural_errors)
  duplicate_columns_only <- write_invented_parquet(session, fixture$core[c("YEAR", "KEY_NIS")])
  on.exit(unlink(duplicate_columns_only), add = TRUE)
  keys_only <- nis_import(session, paths$core, 2022, severity = duplicate_columns_only)
  expect_identical(nis_collect(keys_only, "KEY_NIS")$KEY_NIS, fixture$core$KEY_NIS)
})

test_that("bad component joins fail and clean up their temporary views", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()
  core <- write_invented_parquet(session, fixture$core)
  on.exit(unlink(core), add = TRUE)
  original_views <- DBI::dbListTables(session$connection)
  cases <- list(
    duplicate = rbind(fixture$hospital, fixture$hospital[1L, ]),
    unmatched = fixture$hospital[-1L, ],
    conflicting = transform(fixture$hospital, NIS_STRATUM = NIS_STRATUM + 1L),
    missing = transform(fixture$hospital, HOSP_NIS = NA_character_),
    type_mismatch = transform(fixture$hospital, HOSP_NIS = as.integer(HOSP_NIS))
  )
  messages <- c("duplicate join keys", "unmatched core", "conflicts", "missing join keys", "key types differ")
  for (index in seq_along(cases)) {
    path <- write_invented_parquet(session, cases[[index]])
    on.exit(unlink(path), add = TRUE)
    expect_error(nis_import(session, core, 2022, hospital = path), messages[index])
    expect_identical(DBI::dbListTables(session$connection), original_views)
  }
  extra <- rbind(fixture$hospital,
    data.frame(YEAR = 2022L, HOSP_NIS = "9999", NIS_STRATUM = 1L, HOSP_BEDSIZE = 1L))
  path <- write_invented_parquet(session, extra)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, core, 2022, hospital = path)
  expect_equal(data$joins$hospital$unused_component, 1)
})

test_that("mixed years and mismatched shard schemas fail without leaking views", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()$core
  mixed <- fixture
  mixed$YEAR[1L] <- 2021L
  mixed_path <- write_invented_parquet(session, mixed)
  path <- write_invented_parquet(session, fixture)
  other <- write_invented_parquet(session, fixture[-1L])
  on.exit(unlink(c(mixed_path, path, other)), add = TRUE)
  before <- DBI::dbListTables(session$connection)
  expect_error(nis_import(session, mixed_path, 2022), "mixed YEAR")
  expect_error(nis_import(session, c(path, other), 2022), "identical names")
  expect_error(nis_import(session, c(path, path), 2022), "Repeated")
  expect_identical(DBI::dbListTables(session$connection), before)
})

test_that("paths and column names are safely quoted and source changes are detected", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()$core
  fixture[["odd \" column; --"]] <- seq_len(nrow(fixture))
  path <- write_invented_parquet(session, fixture, tempfile(pattern = "NIS ' ", fileext = ".parquet"))
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  expect_identical(nis_collect(data, "odd \" column; --")[[1L]], seq_len(12L))
  expect_error(nis_collect(data, "missing"), "lacks required")
  expect_error(nis_collect(data, c("YEAR", "YEAR")), "unique")
  expect_error(nis_collect(data, "YEAR", -1), "nonnegative")
  unlink(path)
  expect_error(nis_collect(data, "YEAR"), "changed or disappeared")
  expect_error(nis_validate(data), "changed or disappeared")
})

test_that("BIGINT discharge identifiers retain exact values when collected", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()$core
  DBI::dbWriteTable(session$connection, "big_keys", fixture)
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)
  DBI::dbExecute(session$connection, paste0(
    "COPY (SELECT * REPLACE (CAST(KEY_NIS AS BIGINT) AS KEY_NIS) FROM big_keys) TO ",
    DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"
  ))
  data <- nis_import(session, path, 2022)
  keys <- nis_collect(data, "KEY_NIS")$KEY_NIS
  expect_s3_class(keys, "integer64")
  expect_identical(as.character(keys), fixture$KEY_NIS)
  expect_false(nis_validate(data)$structural_errors)
})

test_that("case collisions are rejected before raw names change", {
  skip_if_not_installed("arrow")
  session <- nis_open()
  on.exit(nis_close(session))
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path), add = TRUE)
  arrow::write_parquet(data.frame(YEAR = 2022L, AGE = 1L, age = 2L), path)
  expect_error(nis_import(session, path, 2022), "case-insensitive field collisions")
})

test_that("nested fields are refused by flat structural import", {
  session <- nis_open()
  on.exit(nis_close(session))
  con <- session$connection
  nested <- tempfile(fileext = ".parquet")
  on.exit(unlink(nested), add = TRUE)
  DBI::dbExecute(con, paste0("COPY (SELECT 2022 AS YEAR, {'part': 1} AS nested) TO ",
    DBI::dbQuoteString(con, nested), " (FORMAT PARQUET)"))
  expect_error(nis_import(session, nested, 2022), "Nested parquet")
})

test_that("matching shards form one relation and empty inputs remain visible", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  first <- write_invented_parquet(session, core[1:6, ])
  second <- write_invented_parquet(session, core[7:12, ])
  empty <- write_invented_parquet(session, core[FALSE, ])
  on.exit(unlink(c(first, second, empty)), add = TRUE)
  pooled <- nis_import(session, c(first, second), 2022)
  expect_equal(nrow(nis_collect(pooled, "YEAR")), 12L)
  expect_false(nis_validate(pooled)$structural_errors)
  report <- nis_validate(nis_import(session, empty, 2022))
  expect_true(report$structural_errors)
  expect_true("empty_core" %in% report$issues$check)
})
