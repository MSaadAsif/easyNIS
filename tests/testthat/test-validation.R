test_that("structural reports retain raw values and report numeric code conversion", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$DISCWT[c(1L, 2L, 3L)] <- c(-1, 0, NA)
  core$KEY_NIS[2L] <- core$KEY_NIS[1L]
  core$HOSP_NIS[3L] <- ""
  core$I10_DX1 <- rep(1L, 12L)
  core$LOS[1L] <- -9L
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  report <- nis_validate(data)
  expect_true(report$structural_errors)
  expect_false(report$analysis_ready)
  expect_equal(report$issues$affected[report$issues$check == "invalid_discharge_weight"], 3)
  expect_equal(report$issues$affected[report$issues$check == "duplicate_discharge_keys"], 1)
  expect_true("code_type" %in% report$issues$check)
  expect_identical(nis_collect(data, "LOS")$LOS[1L], -9L)
})

test_that("floating identifiers beyond exact precision are flagged", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$KEY_NIS <- c(2^53, seq_len(11L))
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  report <- nis_validate(nis_import(session, path, 2022))
  key_issue <- report$issues[report$issues$field == "KEY_NIS" &
                             !is.na(report$issues$field), , drop = FALSE]
  expect_equal(key_issue$affected[key_issue$check == "invalid_identifier"], 1)
  severity <- write_invented_parquet(session, core[c("YEAR", "KEY_NIS")])
  on.exit(unlink(severity), add = TRUE)
  expect_error(nis_import(session, path, 2022, severity = severity), "precision-unsafe")
})

test_that("missing weight fields and invalid identifier types are structured errors", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$DISCWT <- NULL
  core$HOSP_NIS <- rep(TRUE, 12L)
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  report <- nis_validate(nis_import(session, path, 2022))
  expect_true(report$structural_errors)
  expect_true("required_field_absent" %in% report$issues$check)
  expect_true("invalid_identifier" %in% report$issues$check)
})
