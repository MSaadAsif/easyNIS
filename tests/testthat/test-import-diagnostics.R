test_that("failed joins retain machine-readable aggregate diagnostics and clean up", {
  session <- nis_open()
  on.exit(nis_close(session))
  fixture <- nis_synthetic_data()
  core <- write_invented_parquet(session, fixture$core)
  on.exit(unlink(core), add = TRUE)
  before <- DBI::dbListTables(session$connection)
  cases <- list(
    list(data = rbind(fixture$hospital, fixture$hospital[1L, ]),
         check = "duplicate_join_keys", affected = 1, fields = c("YEAR", "HOSP_NIS")),
    list(data = fixture$hospital[-1L, ], check = "unmatched_core", affected = 3,
         fields = c("YEAR", "HOSP_NIS")),
    list(data = transform(fixture$hospital, NIS_STRATUM = NIS_STRATUM + 1L),
         check = "shared_field_conflict", affected = 12, fields = "NIS_STRATUM"),
    list(data = transform(fixture$hospital, HOSP_NIS = NA_character_),
         check = "missing_join_keys", affected = 4, fields = c("YEAR", "HOSP_NIS")),
    list(data = transform(fixture$hospital, HOSP_NIS = "-1"),
         check = "invalid_identifier", affected = 4, fields = "HOSP_NIS"),
    list(data = transform(fixture$hospital, HOSP_NIS = as.integer(HOSP_NIS)),
         check = "join_key_type", affected = NA_real_, fields = "HOSP_NIS"),
    list(data = transform(fixture$hospital, YEAR = 2021L),
         check = "invalid_year", affected = 4, fields = "YEAR"),
    list(data = fixture$hospital[-2L], check = "required_field_absent",
         affected = NA_real_, fields = "HOSP_NIS")
  )
  for (case in cases) {
    path <- write_invented_parquet(session, case$data)
    on.exit(unlink(path), add = TRUE)
    issue <- tryCatch(nis_import(session, core, 2022, hospital = path),
                     nis_structure_error = identity)
    expect_s3_class(issue, "nis_structure_error")
    expect_identical(issue$check, case$check)
    expect_identical(issue$component, "hospital")
    expect_identical(issue$fields, case$fields)
    expect_equal(issue$affected, case$affected)
    expect_identical(names(issue), c("message", "call", "check", "component", "fields", "affected"))
    expect_false(any(vapply(fixture$core$KEY_NIS,
      function(key) grepl(key, issue$message, fixed = TRUE), logical(1))))
    expect_identical(DBI::dbListTables(session$connection), before)
  }
})

test_that("schema failures carry structured field diagnostics without file paths", {
  session <- nis_open()
  on.exit(nis_close(session))
  con <- session$connection
  core <- nis_synthetic_data()$core
  first <- write_invented_parquet(session, core)
  second <- write_invented_parquet(session, core[-1L])
  nested <- tempfile(fileext = ".parquet")
  on.exit(unlink(c(first, second, nested)), add = TRUE)
  DBI::dbExecute(con, paste0("COPY (SELECT 2022 AS YEAR, {'part': 1} AS nested) TO ",
    DBI::dbQuoteString(con, nested), " (FORMAT PARQUET)"))
  cases <- list(
    list(paths = c(first, second), check = "shard_schema_mismatch"),
    list(paths = nested, check = "nested_field")
  )
  for (case in cases) {
    issue <- tryCatch(nis_import(session, case$paths, 2022), nis_structure_error = identity)
    expect_s3_class(issue, "nis_structure_error")
    expect_identical(issue$check, case$check)
    expect_identical(issue$component, "core")
    expect_true(length(issue$fields) > 0L)
    expect_true(is.na(issue$affected))
    expect_false(any(vapply(case$paths, function(path) grepl(path, issue$message, fixed = TRUE),
                            logical(1))))
  }
})
