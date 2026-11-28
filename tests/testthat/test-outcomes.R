test_that("discharge outcomes survive annual Parquet opening and survey design", {
  path <- nis_example(years = c(2015, 2024))
  withr::defer(unlink(path, recursive = TRUE))
  nis <- nis_open(path)
  withr::defer(DBI::dbDisconnect(nis$src$con, shutdown = TRUE))

  codes <- dplyr::tibble(
    HOSP_NIS = 1:12,
    DIED = c(0, 0, 0, 0, 0, 1, 0, 0, NA, -9, 2, 0.5),
    LOS = c(0, 1, 2, 4, 8, 16, NA, 365, 366, -9, Inf, 1.5),
    DISPUNIFORM = c(1, 2, 5, 6, 7, 20, 21, 99, NA, -9, 3, 40)
  )
  expected <- dplyr::mutate(
    codes,
    in_hospital_death = c(rep(FALSE, 5), TRUE, FALSE, FALSE, rep(NA, 4)),
    los_days = c(0, 1, 2, 4, 8, 16, NA, 365, NA, NA, NA, NA),
    discharge_disposition = c(1, 2, 5, 6, 7, 20, 21, 99, rep(NA_real_, 4))
  )
  input <- nis |>
    dplyr::select(-c(DIED, LOS, DISPUNIFORM)) |>
    dplyr::left_join(codes, by = "HOSP_NIS", copy = TRUE) |>
    dplyr::mutate(CCR_NIS = dplyr::if_else(.data$HOSP_NIS == 2L, NA_real_, .data$CCR_NIS))
  outcomes <- nis_outcomes(input)

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
    keep = c(in_hospital_death, los_days, discharge_disposition, TOTCHG, CCR_NIS, I10_DELIVERY, DQTR),
    dollars = 2024
  ))
  expect_type(design$variables$in_hospital_death, "logical")
  delivery <- design$variables$I10_DELIVERY
  mixed_icd9 <- design$variables$YEAR == 2015L & design$variables$DQTR != "Q4"
  expect_type(delivery, "logical")
  expect_identical(is.na(delivery), mixed_icd9)
  expect_false(any(delivery[!mixed_icd9]))
  expect_s3_class(design$variables$discharge_disposition, "factor")
  mortality <- dplyr::summarise(design, rate = srvyr::survey_mean(in_hospital_death, na.rm = TRUE))
  expect_equal(mortality$rate, 1.1 / 9.6)
  expect_equal(
    unname(stats::coef(survey::svyquantile(~los_days, design, 0.5, ci = FALSE, na.rm = TRUE))),
    4
  )
  expect_identical(
    is.na(design$variables$cost_adj),
    design$variables$discharge_disposition %in% "Transfer to another short-term hospital"
  )
  deaths <- design$variables$cost_adj[which(design$variables$in_hospital_death)]
  expect_length(deaths, 16L)
  expect_gt(min(deaths), 0)
})

test_that("adding discharge outcomes does not execute a lazy DuckDB query", {
  input <- duckdb_query_fixture(dplyr::tibble(DIED = 0L, LOS = 1, DISPUNIFORM = 1L)) |>
    dplyr::mutate(DISPUNIFORM = dbplyr::sql("CAST(error('deferred outcome query') AS INTEGER)"))
  outcomes <- nis_outcomes(input)
  expect_s3_class(outcomes, "tbl_lazy")
  expect_error(
    outcomes |> dplyr::select(discharge_disposition) |> dplyr::collect(),
    "deferred outcome query"
  )
})
