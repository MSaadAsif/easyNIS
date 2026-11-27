test_that("companions enrich discharges lazily using the keys for each year", {
  path <- withr::local_tempdir()
  for (year in 2019:2020) {
    annual <- paste0("NIS_", year, ".parquet")
    write_duckdb_parquet(
      data.frame(YEAR = year, KEY_NIS = 1:3, HOSP_NIS = c(1L, 1L, 2L), DISCWT = 5),
      file.path(path, "core", annual)
    )
    write_duckdb_parquet(
      data.frame(HOSP_NIS = 1, HOSP_BEDSIZE = year - 2018L, TOTAL_DISC = 2L, DISCWT = 100),
      file.path(path, "hospital", annual)
    )
    write_duckdb_parquet(
      data.frame(KEY_NIS = "1", APRDRG_Severity = year - 2018L),
      file.path(path, "severity", paste0("YEAR=", year), "part.parquet")
    )
    write_duckdb_parquet(
      data.frame(KEY_NIS = 2L, DX_GROUP = paste0("group-", year)),
      file.path(path, "groups", annual)
    )
  }
  core <- nis_open(file.path(path, "core"), check_release = FALSE)
  enriched <- core |>
    dplyr::filter(KEY_NIS < 3L | YEAR == 2020L) |>
    nis_join_companion(file.path(path, "hospital"), "hospital", HOSP_BEDSIZE) |>
    nis_join_companion(file.path(path, "severity"), "severity", APRDRG_Severity) |>
    nis_join_companion(file.path(path, "groups"), "dx_pr_grps", DX_GROUP)

  expect_s3_class(enriched, "tbl_sql")
  expect_identical(dbplyr::remote_con(enriched), dbplyr::remote_con(core))
  expect_match(dbplyr::sql_render(enriched), "read_parquet")
  observed <- enriched |>
    dplyr::arrange(YEAR, KEY_NIS) |>
    dplyr::collect()
  expect_equal(observed$KEY_NIS, c(1L, 2L, 1L, 2L, 3L))
  expect_equal(observed$HOSP_BEDSIZE, c(1L, 1L, 2L, 2L, NA))
  expect_equal(observed$APRDRG_Severity, c(1L, NA, 2L, NA, NA))
  expect_equal(observed$DX_GROUP, c(NA, "group-2019", NA, "group-2020", NA))
  expect_equal(observed$DISCWT, rep(5, 5))

  expect_error(
    nis_join_companion(core, file.path(path, "hospital"), "hospital", DISCWT),
    "already in the discharge query"
  )
  expect_error(
    nis_join_companion(core, file.path(path, "hospital"), "hospital", TOTAL_DISC),
    "sampled discharge count"
  )
  hospitals <- nis_open(file.path(path, "hospital"), check_release = FALSE)
  expect_error(
    nis_join_companion(hospitals, file.path(path, "hospital"), "hospital", HOSP_BEDSIZE),
    "KEY_NIS"
  )
})

test_that("bad companion keys and wrong annual files fail before collection", {
  path <- withr::local_tempdir()
  core_path <- file.path(path, "core")
  annual <- "NIS_2020.parquet"
  write_duckdb_parquet(
    data.frame(YEAR = 2020L, KEY_NIS = 1L, HOSP_NIS = 1L),
    file.path(core_path, annual)
  )
  core <- nis_open(core_path, check_release = FALSE)
  bad_keys <- list(c(1L, 1L), c("1", "01"), c(1, 1.2), c(1L, NA_integer_))
  for (i in seq_along(bad_keys)) {
    bad <- file.path(path, paste0("bad-", i))
    write_duckdb_parquet(data.frame(KEY_NIS = bad_keys[[i]], FLAG = 1L), file.path(bad, annual))
    expect_error(
      nis_join_companion(core, bad, "severity", FLAG),
      class = "easynis_companion_key"
    )
  }

  wrong_year <- file.path(path, "wrong-year")
  write_duckdb_parquet(data.frame(YEAR = 2019L, KEY_NIS = 1L, FLAG = 1L), file.path(wrong_year, annual))
  expect_error(nis_join_companion(core, wrong_year, "severity", FLAG), "physical `YEAR` values conflict")
  expect_error(nis_join_companion(core, core_path, "severity", FLAG), "separate")
})
