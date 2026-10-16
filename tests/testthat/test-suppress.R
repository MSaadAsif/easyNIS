test_that("nis_suppress masks low unweighted counts and adds the DUA footnote", {
  path <- nis_example(2017)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  design <- nis_open(path) |>
    nis_flag_dx(heart_failure = "I50", position = "principal") |>
    nis_design(heart_failure, keep = c(AGE, DIED, FEMALE))
  table <- gtsummary::tbl_svysummary(
    design,
    by = DIED,
    include = c(AGE, FEMALE),
    statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
  )

  suppressed <- nis_suppress(table, threshold = 10)
  expect_equal(suppressed$table_body$stat_1[[1L]], table$table_body$stat_1[[1L]])
  expect_equal(
    enc2utf8(suppressed$table_body$stat_2[[1L]]),
    enc2utf8(paste0("\u2264", "10"))
  )
  expect_true(any(grepl(
    "HCUP Data Use Agreement small-cell rule",
    unlist(suppressed$table_styling$footnote_header)
  )))
  female_rows <- suppressed$table_body |>
    dplyr::filter(variable == "FEMALE", label == "Female")
  original_female_rows <- table$table_body |>
    dplyr::filter(variable == "FEMALE", label == "Female")
  expect_equal(female_rows$stat_1, original_female_rows$stat_1)
  expect_equal(enc2utf8(female_rows$stat_2), enc2utf8(paste0("\u2264", "10")))
  expect_error(nis_suppress(table, threshold = -1), "non-negative whole number")
})

test_that("nis_suppress masks a low level in a two-level categorical variable", {
  data <- dplyr::tibble(
    group = rep(c("A", "B"), each = 20L),
    category = c(
      rep("Common", 12L), rep("Rare", 8L),
      rep("Common", 11L), rep("Rare", 9L)
    ),
    YEAR = 2017,
    HOSP_NIS = seq_len(40L),
    NIS_STRATUM = rep(1:2, each = 20L),
    DISCWT = 1
  )
  design <- srvyr::as_survey_design(
    data, ids = HOSP_NIS, strata = NIS_STRATUM, weights = DISCWT, nest = TRUE
  )
  table <- gtsummary::tbl_svysummary(
    design, by = group, include = category, percent = "column"
  )
  suppressed <- nis_suppress(table, threshold = 10)

  rare <- dplyr::filter(suppressed$table_body, variable == "category", label == "Rare")
  common <- dplyr::filter(suppressed$table_body, variable == "category", label == "Common")
  expect_equal(nrow(rare), 1L)
  expect_equal(nrow(common), 1L)
  expect_equal(enc2utf8(rare$stat_1), paste0("\u2264", "10"))
  expect_equal(enc2utf8(rare$stat_2), paste0("\u2264", "10"))
  expect_false(grepl("\u2264", common$stat_1))
  expect_false(grepl("\u2264", common$stat_2))
})
