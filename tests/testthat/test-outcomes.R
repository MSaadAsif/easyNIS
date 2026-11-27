test_that("discharge outcomes survive annual Parquet opening and survey design", {
  path <- nis_example(years = c(2015, 2024))
  withr::defer(unlink(path, recursive = TRUE))
  nis <- nis_open(path)
  withr::defer(DBI::dbDisconnect(nis$src$con, shutdown = TRUE))

  codes <- dplyr::tibble(
    HOSP_NIS = 1:12,
    DIED = c(0, 0, 0, 0, 0, 1, 0, 0, NA, -9, 2, NA),
    LOS = c(0, 1, 2, 4, 8, 16, NA, 365, 366, -9, Inf, 1.5),
    DISPUNIFORM = c(1, 2, 5, 6, 7, 20, 21, 99, NA, -9, 3, 40)
  )
  expected <- dplyr::mutate(
    codes,
    in_hospital_death = c(0L, 0L, 0L, 0L, 0L, 1L, 0L, 0L, NA, NA, NA, NA),
    los_days = c(0, 1, 2, 4, 8, 16, NA, 365, NA, NA, NA, NA),
    discharge_disposition = c(
      "Routine home/self-care",
      "Short-term hospital transfer",
      "Other facility transfer",
      "Home health care",
      "Against medical advice",
      "Died in hospital",
      "Court/law enforcement",
      "Alive, destination unknown",
      NA,
      NA,
      NA,
      NA
    )
  )
  input <- nis |>
    dplyr::select(-c(DIED, LOS, DISPUNIFORM)) |>
    dplyr::left_join(codes, by = "HOSP_NIS", copy = TRUE) |>
    dplyr::mutate(CCR_NIS = dplyr::if_else(.data$HOSP_NIS == 2L, NA_real_, .data$CCR_NIS))
  outcomes <- nis_outcomes(input)
  expect_s3_class(outcomes, "tbl_lazy")

  observed <- outcomes |>
    dplyr::select(YEAR, DQTR, dplyr::all_of(names(expected))) |>
    dplyr::distinct() |>
    dplyr::arrange(YEAR, DQTR, HOSP_NIS) |>
    dplyr::collect()
  expect_equal(observed$YEAR, rep(c(2015L, 2024L), each = 48L))
  expect_equal(observed$DQTR, rep(rep(1:4, each = 12L), 2L))
  expect_equal(observed[names(expected)], expected[rep(seq_len(12), 8L), ])
  expect_equal(nis_outcomes(codes), expected)

  design <- suppressMessages(nis_design(
    outcomes,
    cohort = TRUE,
    keep = c(in_hospital_death, los_days, discharge_disposition, TOTCHG, CCR_NIS),
    dollars = 2024
  ))
  mortality <- survey::svymean(~in_hospital_death, design, na.rm = TRUE)
  expect_equal(unname(stats::coef(mortality)), 1.1 / 9.6)
  expect_equal(
    unname(stats::coef(survey::svyquantile(~los_days, design, 0.5, ci = FALSE, na.rm = TRUE))),
    4
  )
  expect_identical(
    is.na(design$variables$cost_adj),
    design$variables$discharge_disposition %in% "Short-term hospital transfer"
  )
  deaths <- design$variables$cost_adj[which(design$variables$in_hospital_death == 1L)]
  expect_length(deaths, 16L)
  expect_gt(min(deaths), 0)
})

test_that("adding discharge outcomes does not execute a lazy DuckDB query", {
  input <- duckdb_query_fixture(dplyr::tibble(DIED = 0L, LOS = 1, DISPUNIFORM = 1L)) |>
    dplyr::mutate(LOS = dbplyr::sql("CAST(error('deferred outcome query') AS DOUBLE)"))
  outcomes <- nis_outcomes(input)
  expect_s3_class(outcomes, "tbl_lazy")
  expect_error(dplyr::collect(outcomes), "deferred outcome query")
})
