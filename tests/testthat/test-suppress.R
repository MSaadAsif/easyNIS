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
  footnote <- unlist(suppressed$table_styling$footnote_header)
  expect_true(any(grepl("review tables for other derivable cells", footnote)))
  expect_true(any(grepl("HCUP Data Use Agreement", footnote)))
  expect_false(any(grepl("overall cell", footnote)))
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

suppress_fixture <- function(data) {
  data$PSU <- seq_len(nrow(data))
  data$STRATUM <- factor((data$PSU - 1L) %% 3L + 1L)
  data$weight <- 1
  survey::svydesign(
    ids = ~PSU, strata = ~STRATUM, weights = ~weight, data = data, nest = TRUE
  )
}

suppress_row <- function(table, variable, label) {
  row <- dplyr::filter(table$table_body, variable == !!variable, label == !!label)
  stopifnot(nrow(row) == 1L)
  row
}

is_masked <- function(cell) identical(enc2utf8(cell), "≤10")

test_that("nis_suppress masks the overall cell beside a masked group cell", {
  # A has 8 events, B has 100: unmasked, the overall 108 minus B's 100 gives A.
  data <- data.frame(
    group = factor(rep(c("A", "B"), c(100L, 200L))),
    event = c(rep(c(TRUE, FALSE), c(8L, 92L)), rep(c(TRUE, FALSE), c(100L, 100L))),
    category = factor(
      c(rep(c("small", "large"), c(8L, 92L)), rep(c("small", "large"), c(100L, 100L))),
      levels = c("small", "large")
    )
  )
  design <- suppress_fixture(data)
  by_table <- gtsummary::tbl_svysummary(
    design, by = group, include = c(event, category), missing = "no"
  )
  table <- gtsummary::add_overall(by_table)

  # The review repro: the overall cell used to stay visible.
  original <- suppress_row(table, "event", "event")
  expect_false(is_masked(original$stat_0))
  suppressed <- nis_suppress(table)

  event <- suppress_row(suppressed, "event", "event")
  expect_true(is_masked(event$stat_1))
  expect_true(is_masked(event$stat_0))
  expect_equal(event$stat_2, original$stat_2)

  small <- suppress_row(suppressed, "category", "small")
  expect_true(is_masked(small$stat_1))
  expect_true(is_masked(small$stat_0))
  expect_false(is_masked(small$stat_2))

  large <- suppress_row(suppressed, "category", "large")
  expect_equal(large$stat_0, suppress_row(table, "category", "large")$stat_0)
  expect_false(any(vapply(large[c("stat_0", "stat_1", "stat_2")], is_masked, logical(1))))

  expect_true(any(grepl(
    "overall cell in the same row",
    unlist(suppressed$table_styling$footnote_header)
  )))

  # Without an overall column there is nothing more to mask.
  alone <- nis_suppress(by_table)
  expect_false("stat_0" %in% names(alone$table_body))
  small_alone <- suppress_row(alone, "category", "small")
  expect_true(is_masked(small_alone$stat_1))
  expect_false(is_masked(small_alone$stat_2))
})

test_that("nis_suppress masks the overall cell with three groups", {
  data <- data.frame(
    group = factor(rep(c("A", "B", "C"), each = 150L)),
    category = factor(
      c(
        rep(c("rare", "common"), c(8L, 142L)),
        rep(c("rare", "common"), c(9L, 141L)),
        rep(c("rare", "common"), c(60L, 90L))
      ),
      levels = c("rare", "common")
    ),
    other = factor(
      c(
        rep(c("rare", "common"), c(50L, 100L)),
        rep(c("rare", "common"), c(9L, 141L)),
        rep(c("rare", "common"), c(60L, 90L))
      ),
      levels = c("rare", "common")
    )
  )
  table <- gtsummary::tbl_svysummary(
    suppress_fixture(data), by = group, include = c(category, other), missing = "no"
  ) |>
    gtsummary::add_overall() |>
    nis_suppress()

  rare <- suppress_row(table, "category", "rare")
  expect_true(all(vapply(rare[c("stat_0", "stat_1", "stat_2")], is_masked, logical(1))))
  expect_false(is_masked(rare$stat_3))

  other_rare <- suppress_row(table, "other", "rare")
  expect_true(is_masked(other_rare$stat_2))
  expect_true(is_masked(other_rare$stat_0))
  expect_false(is_masked(other_rare$stat_1))
  expect_false(is_masked(other_rare$stat_3))

  common <- suppress_row(table, "category", "common")
  expect_false(any(vapply(common[c("stat_0", "stat_1", "stat_2", "stat_3")], is_masked, logical(1))))
})

test_that("nis_suppress keeps the p-value and masks the overall cell with add_p", {
  data <- data.frame(
    group = factor(rep(c("A", "B"), c(100L, 200L))),
    category = factor(
      c(rep(c("small", "large"), c(8L, 92L)), rep(c("small", "large"), c(100L, 100L))),
      levels = c("small", "large")
    )
  )
  table <- gtsummary::tbl_svysummary(
    suppress_fixture(data), by = group, include = category, missing = "no"
  )
  table <- suppressMessages(gtsummary::add_p(table)) |> gtsummary::add_overall()
  expect_true("p.value" %in% names(table$table_body))

  suppressed <- nis_suppress(table)
  small <- suppress_row(suppressed, "category", "small")
  expect_true(is_masked(small$stat_0))
  expect_true(is_masked(small$stat_1))
  expect_false(is_masked(small$stat_2))
  expect_equal(
    suppressed$table_body$p.value,
    table$table_body$p.value
  )
})

test_that("nis_suppress masks the overall cell for continuous and missing rows", {
  data <- data.frame(
    group = factor(rep(c("A", "B"), c(100L, 200L))),
    value = c(seq_len(8L), rep(NA, 92L), seq_len(150L), rep(NA, 50L))
  )
  table <- gtsummary::tbl_svysummary(
    suppress_fixture(data), by = group, include = value
  ) |>
    gtsummary::add_overall() |>
    nis_suppress()

  # Eight non-missing values in A: A's summary and the overall row are masked.
  summary_row <- dplyr::filter(
    table$table_body, variable == "value", row_type == "label"
  )
  expect_true(is_masked(summary_row$stat_1))
  expect_true(is_masked(summary_row$stat_0))
  expect_false(is_masked(summary_row$stat_2))

  # B has 50 missing values, A has 92: neither is small, so nothing is masked.
  missing_row <- dplyr::filter(
    table$table_body, variable == "value", row_type == "missing"
  )
  expect_false(any(vapply(missing_row[c("stat_0", "stat_1", "stat_2")], is_masked, logical(1))))
})
