test_that("lazy selection preserves values and rows and records exact omitted fields", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core[['quoted " field']] <- seq_len(nrow(core))
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  columns <- c('quoted " field', "KEY_NIS", "AGE")
  selected <- nis_select(data, columns)
  expect_identical(selected$schema$column_name, columns)
  expect_identical(collect_by_key(selected, columns), collect_by_key(data, columns))
  expect_identical(selected$selections, list(columns))
  expect_identical(selected$import_schema, data$schema)
  expect_identical(data$schema$column_name, names(core))
  report <- nis_validate(selected, c("AGE", "I10_DX1", "NONEXISTENT"))
  expect_identical(report$fields$state, c("present", "user_omitted", "unverified_absent"))
  expect_identical(report$fields$origin, c("imported", "imported", "unverified"))
  expect_equal(report$fields$record_nulls, c(1, NA, NA))
  expect_true(report$structural_errors)
  expect_false(report$analysis_ready)
  expect_match(report$issues$message[report$issues$field == "DISCWT" &
                                      !is.na(report$issues$field)], "user selection")
  expect_error(nis_collect(selected, "DISCWT"), "lacks required")
  again <- nis_select(selected, "KEY_NIS")
  expect_identical(again$selections, list(columns, "KEY_NIS"))
  expect_identical(nis_validate(again, "AGE")$fields$state, "user_omitted")
})

test_that("absent source fields and record NULLs remain distinct from selection", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$DISCWT <- NULL
  core$LOS[1L] <- -9L
  core$LOS[2L] <- NA_integer_
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  report <- nis_validate(data, c("DISCWT", "LOS", "YEAR"))
  expect_identical(report$fields$state, c("unverified_absent", "present", "present"))
  expect_equal(report$fields$record_nulls, c(NA, 1, 0))
  expect_match(report$issues$message[report$issues$check == "required_field_absent"],
               "source/conversion omission is unverified")
  expect_identical(collect_by_key(data, "LOS")$LOS[1L], -9L)
  for (fields in list(character(), c("YEAR", "YEAR"), NA_character_, 1)) {
    expect_error(nis_validate(data, fields), "unique non-empty")
  }
})

test_that("selected derived flags keep their definition and cannot overwrite omitted history", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$I10_DX1 <- rep("A001", nrow(core))
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  flagged <- nis_flag_codes(data, "condition", invented_code_set(), "principal_diagnosis", "no_match")
  selected <- nis_select(flagged, c("KEY_NIS", "condition"))
  expect_identical(selected$flags, flagged$flags)
  expect_identical(nis_validate(selected, "condition")$fields$origin, "derived")
  dropped <- nis_select(flagged, c("KEY_NIS", "I10_DX1"))
  expect_identical(nis_validate(dropped, "condition")$fields$state, "user_omitted")
  expect_error(nis_flag_codes(dropped, "CONDITION", invented_code_set(),
                              "principal_diagnosis", "no_match"), "conflicts")
  source_dropped <- nis_select(data, c("KEY_NIS", "I10_DX1"))
  for (name in c("AGE", "age", "DISCWT", "I10_DX2")) {
    expect_error(nis_flag_codes(source_dropped, name, invented_code_set(),
                                "principal_diagnosis", "no_match"), "conflicts")
  }
  fresh <- nis_flag_codes(source_dropped, "fresh_flag", invented_code_set(),
                          "principal_diagnosis", "no_match")
  expect_identical(nis_validate(fresh, c("AGE", "fresh_flag"))$fields$origin,
                   c("imported", "derived"))
  expect_identical(nis_validate(fresh, c("AGE", "fresh_flag"))$fields$state,
                   c("user_omitted", "present"))
  for (columns in list(character(), c("YEAR", "YEAR"), "absent", NA_character_)) {
    expect_error(nis_select(data, columns), "unique non-empty|lacks required")
  }
  nis_close(session)
  expect_error(nis_select(data, "YEAR"), "closed")
})
