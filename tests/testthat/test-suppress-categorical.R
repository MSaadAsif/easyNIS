test_that("categorical suppression protects a sole masked level from column totals", {
  skip_if_not_installed("gtsummary")
  skip_if_not_installed("cardx")

  query <- nis_open(nis_example(years = 2019:2020)) |>
    dplyr::mutate(
      eligible = TRUE,
      RACE = dplyr::case_when(
        YEAR == 2019L & KEY_NIS <= 6L ~ 3L,
        YEAR == 2019L & KEY_NIS <= 18L ~ 2L,
        YEAR == 2019L & KEY_NIS <= 47L ~ 1L,
        YEAR == 2019L & KEY_NIS <= 62L ~ 4L,
        YEAR == 2019L & KEY_NIS <= 78L ~ 5L,
        YEAR == 2019L ~ 6L,
        TRUE ~ as.integer((KEY_NIS - 1L) %% 6L + 1L)
      )
    )
  design <- nis_design(query, eligible, keep = c(YEAR, RACE))
  table <- gtsummary::tbl_svysummary(
    design,
    by = YEAR,
    include = RACE,
    statistic = RACE ~ "{n_unweighted}",
    missing = "no"
  ) |>
    gtsummary::add_overall(statistic = RACE ~ "{n_unweighted}") |>
    gtsummary::modify_header(gtsummary::all_stat_cols() ~ "{level}: {n_unweighted}")
  levels <- table$table_body$row_type == "level"
  expect_identical(table$table_body$stat_1[levels], c("29", "12", "6", "15", "16", "18"))
  expect_true("2019: 96" %in% table$table_styling$header$label)

  result <- nis_suppress(table)$table_body
  expect_identical(enc2utf8(result$stat_1[levels]), c("29", "Masked", "\u226410", "15", "16", "18"))
  expect_identical(result$stat_2[levels], rep("16", 6L))
  expect_identical(result$stat_0[levels], c("45", "Masked", "Masked", "31", "32", "34"))

  overall <- gtsummary::tbl_svysummary(
    subset(design, YEAR == 2019L),
    include = RACE,
    statistic = RACE ~ "{n_unweighted}",
    missing = "no"
  )
  expect_identical(
    enc2utf8(nis_suppress(overall)$table_body$stat_0[levels]),
    c("29", "Masked", "\u226410", "15", "16", "18")
  )
})
