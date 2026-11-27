test_that("selections compose from an invented lazy cohort to masked cells", {
  records <- nis_open(nis_example(years = 2019:2020))
  records <- dplyr::mutate(records, unused = dbplyr::sql("error('unused discharge field')"))
  periods <- c("YEAR", "DQTR")
  cells <- nis_cell_counts(records, by = tidyselect::all_of(periods))
  expect_identical(names(cells), c(periods, "n", "hospitals"))
  expect_equal(sum(cells$n), nis_cell_counts(records, by = tidyselect::any_of("absent"))$n)
  expect_error(nis_cell_counts(records, by = absent), "absent")
  expect_error(nis_cell_counts(records, by = c(period = YEAR)), "rename")

  estimates <- dplyr::mutate(cells, estimate_total = 100, estimate_se = 3)
  count <- "n"
  masked <- nis_suppress(
    estimates,
    threshold = max(cells$n),
    count_col = tidyselect::all_of(count),
    hospital_col = hospitals,
    weighted_cols = tidyselect::starts_with("estimate_"),
    by = YEAR
  )
  expect_identical(names(masked), names(estimates))
  expect_true(all(grepl("^\u2264", masked$estimate_total)))
  expect_identical(masked$estimate_total, masked$estimate_se)
  expect_error(nis_suppress(estimates, count_col = absent), "absent")
  expect_error(nis_suppress(estimates, count_col = c(count = n)), "rename")
  expect_error(nis_suppress(estimates, count_col = tidyselect::any_of("absent")), "count_col")
})

test_that("diagnostic selectors use source names on a lazy schema", {
  records <- nis_open(nis_example(years = 2019:2020))
  periods <- c("DQTR", "YEAR")
  codes <- c(pacing = "0JH60")
  for (output in c("summary", "inventory")) {
    audit <- nis_audit_code_transition(records, codes, by = tidyselect::all_of(periods), output = output)
    expect_identical(names(audit)[1:2], periods)
    expect_gt(sum(audit$n_unweighted), 0)
  }
  expect_error(nis_audit_code_transition(records, codes, by = absent), "absent")
  expect_error(nis_audit_code_transition(records, codes, by = c(period = YEAR)), "rename")
  expect_error(nis_audit_code_transition(records, codes, by = tidyselect::any_of("absent")), "by")

  outcomes <- c("ELECTIVE", "DIED", "absent")
  rates <- nis_audit_dx_position(records, "I50", outcomes = tidyselect::any_of(outcomes))
  expect_identical(
    tail(names(rates), 4),
    c(
      "ELECTIVE_rate_unweighted",
      "ELECTIVE_rate_weighted",
      "DIED_rate_unweighted",
      "DIED_rate_weighted"
    )
  )
  expect_equal(nis_audit_dx_position(records, "I50", outcomes = NULL), rates[1:5])
  expect_error(nis_audit_dx_position(records, "I50", outcomes = tidyselect::all_of(outcomes)), "absent")
  expect_error(nis_audit_dx_position(records, "I50", outcomes = c(death = DIED)), "rename")
})

test_that("companion selectors use the union of available non-key fields", {
  core <- nis_open(nis_example(years = 2019:2020)) |>
    dplyr::select(YEAR, KEY_NIS, HOSP_NIS)
  path <- withr::local_tempdir()
  hospitals <- core |>
    dplyr::distinct(YEAR, HOSP_NIS) |>
    dplyr::collect()
  write_duckdb_parquet(
    dplyr::mutate(hospitals[hospitals$YEAR == 2019L, ], HOSP_REGION = 2L),
    file.path(path, "NIS_2019.parquet")
  )
  write_duckdb_parquet(
    dplyr::mutate(hospitals[hospitals$YEAR == 2020L, ], HOSP_BEDSIZE = 1L),
    file.path(path, "NIS_2020.parquet")
  )
  joined <- nis_join_companion(core, path, "hospital", nis_vars_hospital())
  expect_s3_class(joined, "tbl_sql")
  expect_match(dbplyr::sql_render(joined), "read_parquet")
  by_year <- joined |>
    dplyr::distinct(YEAR, HOSP_REGION, HOSP_BEDSIZE) |>
    dplyr::arrange(YEAR) |>
    dplyr::collect()
  expect_equal(by_year$HOSP_REGION, c(2L, NA_integer_))
  expect_equal(by_year$HOSP_BEDSIZE, c(NA_integer_, 1L))
  expect_error(nis_join_companion(core, path, "hospital", absent), "absent")
  expect_error(nis_join_companion(core, path, "hospital", c(size = HOSP_BEDSIZE)), "rename")
  expect_error(nis_join_companion(core, path, "hospital", tidyselect::any_of("absent")), "columns")
})
