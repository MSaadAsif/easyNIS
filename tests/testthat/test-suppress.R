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

test_that("nis_suppress masks overall cells with add_p and keeps no-by support", {
  make_group <- function(group, common, tiny) {
    data.frame(
      group = group,
      category = c(rep("common", common), rep("tiny", tiny)),
      stringsAsFactors = FALSE
    )
  }
  data <- rbind(make_group("A", 11L, 1L), make_group("B", 11L, 0L))
  data$group <- factor(data$group, levels = c("A", "B"))
  data$category <- factor(data$category, levels = c("common", "tiny"))
  data$PSU <- seq_len(nrow(data))
  data$STRATUM <- factor((data$PSU - 1L) %% 3L + 1L)
  data$weight <- 1
  design <- survey::svydesign(
    ids = ~PSU, strata = ~STRATUM, weights = ~weight, data = data, nest = TRUE
  )

  table <- gtsummary::tbl_svysummary(
    design,
    by = group,
    include = category,
    statistic = list(gtsummary::all_categorical() ~ "{n_unweighted} ({p}%)"),
    missing = "no"
  )
  table <- suppressMessages(gtsummary::add_p(table))
  table <- gtsummary::add_overall(table)
  expect_true("p.value" %in% names(table$table_body))

  suppressed <- nis_suppress(table)
  tiny <- dplyr::filter(suppressed$table_body, variable == "category", label == "tiny")
  expect_equal(nrow(tiny), 1L)
  expect_equal(enc2utf8(tiny$stat_0[[1L]]), "\u226410")
  expect_equal(enc2utf8(tiny$stat_1[[1L]]), "\u226410")
  expect_equal(enc2utf8(tiny$stat_2[[1L]]), "\u226410")
  expect_true("p.value" %in% names(suppressed$table_body))

  no_by <- gtsummary::tbl_svysummary(
    design,
    include = category,
    statistic = list(gtsummary::all_categorical() ~ "{n_unweighted} ({p}%)"),
    missing = "no"
  ) |>
    nis_suppress()
  no_by_tiny <- dplyr::filter(
    no_by$table_body, variable == "category", label == "tiny"
  )
  expect_equal(nrow(no_by_tiny), 1L)
  expect_equal(enc2utf8(no_by_tiny$stat_0[[1L]]), "\u226410")
})
