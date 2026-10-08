cohort_fixture <- function(year = 2022) {
  core <- nis_synthetic_data(year)$core
  core$I10_DX1 <- c("A001", "A0019", "B209", NA, "", "B209", " a00.1 ",
                    "A00.1", "A001", "B209", NA, "B209")
  core$I10_DX2 <- c(NA, "B209", "A001", NA, " ", "", "B209", "B209",
                    "B209", "B209", "B209", "A0019")
  if ("I10_DX3" %in% names(core)) core$I10_DX3 <- rep("B209", 12L)
  if ("I10_DX4" %in% names(core)) {
    core$I10_DX4 <- rep("B209", 12L)
    core$I10_DX4[10L] <- "A001"
  }
  core$I10_PR1 <- c("0012345", "0123456", rep(NA_character_, 10L))
  for (field in setdiff(grep("^I10_PR", names(core), value = TRUE), "I10_PR1")) {
    core[[field]] <- rep(NA_character_, 12L)
  }
  core$DQTR <- rep(1:4, 3L)
  core
}

test_that("literal exact and prefix SQL flags agree with R and keep the full population", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- cohort_fixture()
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  for (matching in c("exact", "prefix")) {
    for (policy in c("no_match", "unknown_if_all_missing", "unknown_if_any_missing")) {
      set <- invented_code_set(match = matching)
      flagged <- nis_flag_codes(data, "condition", set, "any_diagnosis", policy, slots = 1:2)
      observed <- nis_collect(flagged, c("KEY_NIS", "condition"))
      reference <- apply(core[c("I10_DX1", "I10_DX2")], 1L, function(row) {
        absent <- is.na(row) | trimws(row) == ""
        present <- row[!absent]
        positive <- if (matching == "exact") any(present == "A001") else
          any(startsWith(present, "A001"))
        if (positive) TRUE else if (policy == "unknown_if_all_missing" && all(absent) ||
                                   policy == "unknown_if_any_missing" && any(absent)) NA else FALSE
      })
      expect_identical(observed$condition, reference)
      expect_identical(observed$KEY_NIS, core$KEY_NIS)
      expect_identical(flagged$flags$condition$slots, c("I10_DX1", "I10_DX2"))
      expect_identical(flagged$flags$condition$slot_policy, "explicit_common_slots")
    }
  }
  expect_false("condition" %in% data$schema$column_name)
  expect_identical(nis_collect(data, names(core)), core)
})

test_that("normalization, scope and procedure zeros have explicit behavior", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- cohort_fixture()
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  set <- invented_code_set(normalize = TRUE)
  principal <- nis_flag_codes(data, "principal", set, "principal_diagnosis", "no_match")
  expect_identical(nis_collect(principal, "principal")$principal,
                   seq_len(12L) %in% c(1L, 7L, 8L, 9L))
  secondary <- nis_flag_codes(data, "secondary", set, "secondary_diagnosis", "no_match")
  expect_identical(nis_collect(secondary, "secondary")$secondary,
                   seq_len(12L) %in% c(3L, 10L))
  procedures <- nis_flag_codes(data, "procedure", invented_code_set("0012345", "ICD10PCS"),
                              "any_procedure", "no_match")
  expect_identical(nis_collect(procedures, "procedure")$procedure, seq_len(12L) == 1L)
  quoted <- nis_flag_codes(data, "flag \"; --", set, "any_diagnosis", "no_match")
  expect_type(nis_collect(quoted, "flag \"; --")[[1L]], "logical")
  expect_false(nis_validate(quoted)$analysis_ready)
})

test_that("common slots expose sensitivity to available slots across years", {
  session <- nis_open()
  on.exit(nis_close(session))
  set <- invented_code_set()
  common <- list()
  for (year in c(2017, 2022)) {
    core <- cohort_fixture(year)
    path <- write_invented_parquet(session, core)
    on.exit(unlink(path), add = TRUE)
    data <- nis_import(session, path, year)
    restricted <- nis_flag_codes(data, "common", set, "any_diagnosis", "no_match", 1:2)
    common[[as.character(year)]] <- nis_collect(restricted, "common")$common
    full <- nis_flag_codes(data, "full", set, "any_diagnosis", "no_match")
    expect_identical(nis_collect(full, "full")$full[10L], year == 2022)
    expect_identical(full$flags$full$slot_policy, "observed_available")
  }
  expect_identical(common[["2017"]], common[["2022"]])
})

test_that("restricted applicability requires valid quarters and marks other periods unknown", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- cohort_fixture()
  core$I10_DX1 <- rep("A001", 12L)
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  set <- invented_code_set(valid_quarters = 2:3)
  flag <- nis_flag_codes(data, "condition", set, "principal_diagnosis", "no_match")
  expect_identical(nis_collect(flag, "condition")$condition,
                   rep(c(NA, TRUE, TRUE, NA), 3L))
  for (quarter in c(NA, 1.5, 5)) {
    core$DQTR[1L] <- quarter
    invalid <- write_invented_parquet(session, core)
    on.exit(unlink(invalid), add = TRUE)
    expect_error(nis_flag_codes(nis_import(session, invalid, 2022), "condition", set,
                                "principal_diagnosis", "no_match"), "valid DQTR")
  }
  core$DQTR <- NULL
  absent <- write_invented_parquet(session, core)
  on.exit(unlink(absent), add = TRUE)
  expect_error(nis_flag_codes(nis_import(session, absent, 2022), "condition", set,
                              "principal_diagnosis", "no_match"), "DQTR")
})

test_that("ambiguity in scope, policy, applicability and fields fails before matching", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- cohort_fixture()
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  set <- invented_code_set()
  expect_error(nis_flag_codes(data, "x", set), "explicit.*scope")
  expect_error(nis_flag_codes(data, "x", set, "any_diagnosis"), "explicit.*missing")
  expect_error(nis_flag_codes(data, "year", set, "any_diagnosis", "no_match"), "conflicts")
  expect_error(nis_flag_codes(data, "x", set, "any_procedure", "no_match"), "incompatible")
  set$valid_years <- 2021L
  expect_error(nis_flag_codes(data, "x", set, "any_diagnosis", "no_match"), "applicability")
  set <- invented_code_set()
  for (slots in list(0, c(1, 1), 5, 1.5)) {
    expect_error(nis_flag_codes(data, "x", set, "any_diagnosis", "no_match", slots),
                 "slots|whole")
  }
  expect_error(nis_flag_codes(data, "x", set, "principal_diagnosis", "no_match", 2), "slots")
  core$I10_DX1 <- rep(1L, 12L)
  numeric <- write_invented_parquet(session, core)
  on.exit(unlink(numeric), add = TRUE)
  expect_error(nis_flag_codes(nis_import(session, numeric, 2022), "x", set,
                              "principal_diagnosis", "no_match"), "character source slots")
  core$I10_DX1 <- NULL
  absent <- write_invented_parquet(session, core)
  on.exit(unlink(absent), add = TRUE)
  expect_error(nis_flag_codes(nis_import(session, absent, 2022), "x", set,
                              "principal_diagnosis", "no_match"), "No source slots")
})
