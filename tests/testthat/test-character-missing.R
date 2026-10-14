collect_quality_flag <- function(data, expected, core) {
  observed <- nis_collect(data, c('KEY_NIS', 'quality_flag'), limit = nrow(core))
  testthat::expect_identical(observed$quality_flag, expected[match(observed$KEY_NIS, core$KEY_NIS)])
}

test_that('character quality markers are explicit, unknown and raw-preserving', {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$I10_DX1 <- c('invl', 'incn', ' invl\t', 'I10', 'J00', '', NA,
    'I11.9', 'incn ', 'I20', '\t', 'J001')
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  for (normalize in c(FALSE, TRUE)) {
    codes <- nis_code_set('I', 'ICD10CM', 2022, 'test-1', 'invented', 'test',
      match = 'prefix', normalize = normalize)
    refusal <- tryCatch(nis_flag_codes(data, 'quality_flag', codes,
      'principal_diagnosis', 'no_match'), nis_structure_error = identity)
    expect_s3_class(refusal, 'nis_structure_error')
    expect_identical(refusal$check, 'invalid_code_syntax')
    expect_equal(refusal$affected, 4)
    for (missing in c('no_match', 'unknown_if_all_missing', 'unknown_if_any_missing')) {
      blank <- if (missing == 'no_match') FALSE else NA
      expected <- c(NA, NA, NA, TRUE, FALSE, blank, blank, TRUE, NA, TRUE, blank, FALSE)
      flagged <- nis_flag_codes(data, 'quality_flag', codes, 'principal_diagnosis', missing,
        special_missing = 'hcup_character')
      collect_quality_flag(flagged, expected, core)
      raw <- nis_collect(flagged, c('KEY_NIS', 'I10_DX1'), limit = 12)
      expect_identical(raw$I10_DX1, core$I10_DX1[match(raw$KEY_NIS, core$KEY_NIS)])
      declaration <- flagged$flags$quality_flag$special_missing
      expect_identical(declaration$values, c(invalid = 'invl', inconsistent = 'incn'))
      expect_identical(declaration$years, 2017:2022)
      expect_identical(declaration$matching, 'ASCII_trim_then_exact_lowercase')
      expect_identical(declaration$flag_rule, 'unknown_unless_positive')
      expect_null(data$flags)
    }
  }
})

test_that('quality markers respect selected slots and positive precedence', {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$I10_DX1 <- rep('invl', 12)
  core$I10_DX2 <- rep(c('I10', 'J00', 'incn', NA), 3)
  core$I10_PR1 <- rep(c('invl', 'incn', '0ABCDEF', '1ABCDEF'), 3)
  core$I10_PR2 <- rep('0ABCDEF', 12)
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  diagnosis <- nis_code_set('I', 'ICD10CM', 2022, 'test', 'invented', 'test', match = 'prefix')
  any_dx <- nis_flag_codes(data, 'quality_flag', diagnosis, 'any_diagnosis', 'no_match',
    slots = 1:2, special_missing = 'hcup_character')
  collect_quality_flag(any_dx, rep(c(TRUE, NA, NA, NA), 3), core)
  secondary <- nis_flag_codes(data, 'quality_flag', diagnosis, 'secondary_diagnosis', 'no_match',
    slots = 2, special_missing = 'hcup_character')
  collect_quality_flag(secondary, rep(c(TRUE, FALSE, NA, FALSE), 3), core)
  procedure <- nis_code_set('0', 'ICD10PCS', 2022, 'test', 'invented', 'test', match = 'prefix')
  one_pr <- nis_flag_codes(data, 'quality_flag', procedure, 'any_procedure', 'no_match',
    slots = 1, special_missing = 'hcup_character')
  collect_quality_flag(one_pr, rep(c(NA, NA, TRUE, FALSE), 3), core)
  both_pr <- nis_flag_codes(data, 'quality_flag', procedure, 'any_procedure', 'no_match',
    slots = 1:2, special_missing = 'hcup_character')
  collect_quality_flag(both_pr, rep(TRUE, 12), core)
})

test_that('opt-in markers do not excuse case aliases or other malformed values', {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  core <- nis_synthetic_data()$core
  core$I10_DX1 <- rep('I10', 12)
  core$I10_DX2 <- rep('I10', 12)
  codes <- nis_code_set('I', 'ICD10CM', 2022, 'test', 'invented', 'test', match = 'prefix', normalize = TRUE)
  for (invalid in c('INVL', 'Incn', 'invlDX', '.A', 'A', '123', 'I10.')) {
    current <- core
    current$I10_DX1[1] <- invalid
    path <- write_invented_parquet(session, current)
    paths <- c(paths, path)
    data <- nis_import(session, path, 2022)
    refusal <- tryCatch(nis_flag_codes(data, 'quality_flag', codes, 'any_diagnosis', 'no_match',
      slots = 1:2, special_missing = 'hcup_character'), nis_structure_error = identity)
    expect_s3_class(refusal, 'nis_structure_error')
    expect_identical(refusal$check, 'invalid_code_syntax')
    expect_equal(refusal$affected, 1)
  }
  for (choice in list(NA_character_, TRUE, '', character(), c('reject', 'hcup_character'), 'other')) {
    expect_error(nis_flag_codes(data, 'quality_flag', codes, 'principal_diagnosis', 'no_match',
      special_missing = choice), 'special_missing')
  }
})

test_that('quality marker recognition is independent of connection collation', {
  session <- nis_open()
  on.exit(nis_close(session))
  DBI::dbExecute(session$connection, "SET default_collation='nocase'")
  core <- nis_synthetic_data()$core
  core$I10_DX1 <- rep(c('invl', 'incn', ' invl\t', 'I10'), 3)
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  codes <- nis_code_set('I', 'ICD10CM', 2022, 'test', 'invented', 'test',
    match = 'prefix', normalize = TRUE)
  flagged <- nis_flag_codes(data, 'quality_flag', codes, 'principal_diagnosis',
    'no_match', special_missing = 'hcup_character')
  collect_quality_flag(flagged, rep(c(NA, NA, NA, TRUE), 3), core)
  core$I10_DX1[1] <- 'INVL'
  alias_path <- write_invented_parquet(session, core)
  on.exit(unlink(alias_path), add = TRUE)
  alias_data <- nis_import(session, alias_path, 2022)
  refusal <- tryCatch(nis_flag_codes(alias_data, 'quality_flag', codes,
    'principal_diagnosis', 'no_match', special_missing = 'hcup_character'),
    nis_structure_error = identity)
  expect_s3_class(refusal, 'nis_structure_error')
  expect_identical(refusal$check, 'invalid_code_syntax')
  expect_equal(refusal$affected, 1)
})

test_that('character convention is explicit for every initial year label', {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  for (year in 2017:2022) {
    core <- nis_synthetic_data(year)$core
    core$I10_DX1 <- rep(c('invl', 'incn', 'I10', 'J00'), 3)
    path <- write_invented_parquet(session, core)
    paths <- c(paths, path)
    data <- nis_import(session, path, year)
    codes <- nis_code_set('I', 'ICD10CM', year, 'test', 'invented', 'test', match = 'prefix')
    flagged <- nis_flag_codes(data, 'quality_flag', codes, 'principal_diagnosis', 'no_match',
      special_missing = 'hcup_character')
    collect_quality_flag(flagged, rep(c(NA, NA, TRUE, FALSE), 3), core)
  }
})
