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
    expect_false(any(fixture$core$KEY_NIS %in% issue$message))
    expect_identical(DBI::dbListTables(session$connection), before)
  }
})
