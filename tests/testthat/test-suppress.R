test_that("suppression thresholds preserve scalar validation", {
  inputs <- list(
    null = NULL, logical_na = NA, integer_na = NA_integer_, real_na = NA_real_,
    nan = NaN, positive_infinity = Inf, negative_infinity = -Inf,
    negative_integer = -1L, negative_fraction = -0.5, zero_double = 0,
    zero_integer = 0L, positive_fraction = 0.5, one_double = 1,
    one_integer = 1L, integer = 2L, integer_max = .Machine$integer.max,
    over_integer_max = as.double(.Machine$integer.max) + 1,
    empty_double = numeric(), empty_integer = integer(),
    two_values = c(1, 2), character = "10", empty_character = "",
    logical_true = TRUE, logical_false = FALSE, factor = factor("1"),
    list = list(1), complex = 1 + 0i, date = as.Date("1970-01-01"),
    one_by_one_matrix = matrix(1), matrix_length_two = matrix(c(1, 2)),
    raw = as.raw(1), max_fraction = .Machine$integer.max - 0.5
  )
  expected <- c(
    null = FALSE, logical_na = FALSE, integer_na = FALSE, real_na = FALSE,
    nan = FALSE, positive_infinity = FALSE, negative_infinity = FALSE,
    negative_integer = FALSE, negative_fraction = FALSE, zero_double = TRUE,
    zero_integer = TRUE, positive_fraction = FALSE, one_double = TRUE,
    one_integer = TRUE, integer = TRUE, integer_max = TRUE,
    over_integer_max = FALSE, empty_double = FALSE, empty_integer = FALSE,
    two_values = FALSE, character = FALSE, empty_character = FALSE,
    logical_true = FALSE, logical_false = FALSE, factor = FALSE, list = FALSE,
    complex = FALSE, date = FALSE, one_by_one_matrix = TRUE,
    matrix_length_two = FALSE, raw = FALSE, max_fraction = FALSE
  )

  expect_identical(
    vapply(inputs, easyNIS:::is_valid_suppress_threshold, logical(1)),
    expected
  )
})

test_that("nis_suppress validates inputs without survey summary cards", {
  expect_error(nis_suppress(data.frame()), "count_col")
  expect_error(
    nis_suppress(structure(list(), class = "tbl_svysummary")),
    "tbl_svysummary"
  )
})

test_that("suppression uses unweighted boundary and missing counts", {
  data <- data.frame(
    group = rep(c("A", "B"), each = 12L),
    value = c(seq_len(10L), NA, NA, seq_len(11L), NA),
    binary = c(rep(1L, 10L), 0L, 0L, rep(1L, 11L), 0L),
    PSU = seq_len(24L),
    weight = 100
  )
  design <- survey::svydesign(ids = ~PSU, weights = ~weight, data = data)
  table <- gtsummary::tbl_svysummary(
    design,
    by = group,
    include = c(value, binary),
    type = list(value ~ "continuous", binary ~ "dichotomous"),
    value = list(binary ~ 1L),
    missing = "ifany"
  )
  expect_message(
    suppressed <- nis_suppress(table), "two-hospital rule"
  )
  labels <- suppressed$table_body$row_type == "label"
  expect_identical(enc2utf8(suppressed$table_body$stat_1[labels]),
    rep("\u226410", 2L))
  expect_identical(suppressed$table_body$stat_2[labels],
    table$table_body$stat_2[labels])
  missing <- suppressed$table_body$row_type == "missing"
  expect_true(any(missing))
  expect_true(all(enc2utf8(suppressed$table_body$stat_1[missing]) == "\u226410"))
  expect_true(all(enc2utf8(suppressed$table_body$stat_2[missing]) == "\u226410"))
  for (threshold in list(NA_real_, Inf, 0.5, "10", c(1, 2))) {
    expect_error(nis_suppress(table, threshold), "non-negative whole number")
  }
})

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

test_that("nis_suppress handles data frames and paired weighted columns", {
  data <- dplyr::tibble(
    group = c("A", "A", "B"),
    n = c(4, 20, 0),
    estimate = c(8.25, 40.5, 0)
  )
  result <- nis_suppress(data, count_col = "n", weighted_cols = "estimate",
    by = "group", secondary = FALSE)

  expect_s3_class(result, "tbl_df")
  expect_identical(result$group, data$group)
  expect_identical(result$n, c("\u226410", "20", "\u226410"))
  expect_identical(result$estimate, c("\u226410", "40.5", "\u226410"))
})

test_that("nis_suppress applies data-frame complementary masking by stratum", {
  data <- data.frame(
    group = rep(c("A", "B"), each = 3L),
    n = c(4, 20, 30, 1, 6, 40),
    estimate = c(4.5, 20.5, 30.5, 1.5, 6.5, 40.5)
  )
  result <- nis_suppress(data, threshold = 5, count_col = "n",
    weighted_cols = "estimate", by = "group")

  expect_identical(result$n,
    c("\u22645", "Masked", "30", "\u22645", "Masked", "40"))
  expect_identical(result$estimate,
    c("\u22645", "Masked", "30.5", "\u22645", "Masked", "40.5"))
  expect_identical(result$group, data$group)
  expect_identical(class(result), class(data))
})

test_that("nis_suppress applies the two-hospital rule to data-frame cells", {
  data <- data.frame(
    group = c("one", "two", "small", "safe"),
    n = c(14, 14, 4, 20),
    hospitals = c(1, 2, 1, 3),
    estimate = c(14.5, 14.5, 4.5, 20.5)
  )
  result <- nis_suppress(
    data, count_col = "n", hospital_col = "hospitals",
    weighted_cols = "estimate", secondary = FALSE
  )

  expect_identical(result$n,
    c("<2 hospitals", "14", "\u226410", "20"))
  expect_identical(result$estimate,
    c("<2 hospitals", "14.5", "\u226410", "20.5"))
})

test_that("zero-count cells are suppressed", {
  data <- data.frame(n = c(0, 14), hospitals = c(0, 1))
  result <- nis_suppress(data, count_col = "n", hospital_col = "hospitals")
  expect_identical(result$n, c("\u226410", "<2 hospitals"))
  expect_identical(result$hospitals, c("\u226410", "<2 hospitals"))
})

test_that("nis_suppress rejects invalid data-frame discharge counts", {
  invalid_counts <- list(NA_real_, Inf, -1, 1.5)
  for (count in invalid_counts) {
    data <- data.frame(n = count)
    expect_error(
      nis_suppress(data, count_col = "n"),
      "finite, non-negative whole counts without missing values"
    )
  }
})

test_that("hospital primary masks join complementary masking", {
  data <- data.frame(
    group = c("A", "A", "A"), n = c(14, 18, 25),
    hospitals = c(1, 3, 4), estimate = c(14.5, 18.5, 25.5)
  )
  result <- nis_suppress(
    data, count_col = "n", hospital_col = "hospitals",
    weighted_cols = "estimate", by = "group"
  )
  expect_identical(result$n, c("<2 hospitals", "Masked", "25"))
  expect_identical(result$estimate, c("<2 hospitals", "Masked", "25.5"))
})

test_that("nis_suppress rejects missing hospital counts explicitly", {
  data <- data.frame(n = 14, hospitals = NA_real_)
  expect_error(
    nis_suppress(data, count_col = "n", hospital_col = "hospitals"),
    "without missing values"
  )
})

test_that("nis_cell_counts uses year-scoped hospital identities", {
  records <- data.frame(
    YEAR = c(rep(2020, 7), rep(2021, 7), 2021),
    HOSP_NIS = c(rep(1, 7), rep(c(1, 2), c(4, 3)), 2),
    group = c(rep("A", 14), "B")
  )
  counts <- nis_cell_counts(records, by = "group")
  expect_identical(counts$group, c("A", "B"))
  expect_identical(counts$n, c(14L, 1L))
  expect_identical(counts$hospitals, c(3L, 1L))
  masked <- nis_suppress(
    counts, count_col = "n", hospital_col = "hospitals", secondary = FALSE
  )
  expect_identical(masked$n, c("14", "\u226410"))
  expect_identical(masked$hospitals, c("3", "\u226410"))
})

test_that("nis_cell_counts excludes zero-domain placeholder rows", {
  data <- dplyr::tibble(
    YEAR = c(2017, 2017, 2017),
    HOSP_NIS = c(1, 2, 3),
    NIS_STRATUM = c(1, 1, 1),
    DISCWT = c(1, 1, 1),
    eligible = c(TRUE, TRUE, FALSE),
    group = c("A", "A", "A")
  )
  design <- nis_design(data, eligible, keep = group)
  counts <- nis_cell_counts(design, by = "group")
  cohort_counts <- nis_cell_counts(data[data$eligible, ], by = "group")

  expect_equal(counts, cohort_counts)
  expect_identical(counts$n, 2L)
  expect_identical(counts$hospitals, 2L)
  expect_equal(nrow(attr(design, "nis_placeholder_rows")), 1L)
  expect_false(attr(design, "nis_placeholder_rows")$.in_cohort[[1L]])
})

test_that("nis_cell_counts handles an unstratified cell and validates its inputs", {
  records <- data.frame(YEAR = c(2020, 2020, 2021), HOSP_NIS = c(1, 2, 1))

  overall <- nis_cell_counts(records, by = character())
  expect_equal(overall$n, 3L)
  expect_equal(overall$hospitals, 3L)
  expect_error(nis_cell_counts(records, by = NA_character_), "cell-defining columns")
  expect_error(nis_cell_counts(records, by = "missing"), "missing")
  expect_error(nis_cell_counts(records["YEAR"], by = character()), "HOSP_NIS")
  expect_error(nis_cell_counts(list(records), by = character()), "record-level data frame")
  expect_error(nis_cell_counts(transform(records, YEAR = "2020"), by = character()),
    "finite positive")
  expect_error(nis_cell_counts(transform(records, YEAR = NA_real_), by = character()),
    "finite positive")
  expect_error(nis_cell_counts(transform(records, HOSP_NIS = Inf), by = character()),
    "finite positive")
  expect_error(nis_cell_counts(transform(records, HOSP_NIS = NA_real_), by = character()),
    "finite positive")
  expect_error(nis_cell_counts(transform(records, HOSP_NIS = 0), by = character()),
    "finite positive")
})

test_that("nis_suppress groups interleaved data-frame strata without reordering", {
  data <- data.frame(
    group = c("A", "B", "A", "B"),
    n = c(2, 3, 20, 30),
    estimate = c(2.5, 3.5, 20.5, 30.5)
  )
  result <- nis_suppress(data, threshold = 5, count_col = "n",
    weighted_cols = "estimate", by = "group")

  expect_identical(class(result), class(data))
  expect_identical(result$group, data$group)
  expect_identical(result$n, c("\u22645", "\u22645", "Masked", "Masked"))
  expect_identical(result$estimate,
    c("\u22645", "\u22645", "Masked", "Masked"))
})

test_that("nis_suppress skips complementary masking with multiple primary rows", {
  data <- data.frame(n = c(1, 4, 20), estimate = c(1.5, 4.5, 20.5))
  result <- nis_suppress(data, count_col = "n", weighted_cols = "estimate")
  expect_identical(result$n, c("\u226410", "\u226410", "20"))
  expect_identical(result$estimate, c("\u226410", "\u226410", "20.5"))

  no_secondary <- nis_suppress(
    data.frame(n = c(4, 20), estimate = c(4.5, 20.5)),
    count_col = "n", weighted_cols = "estimate", secondary = FALSE
  )
  expect_identical(no_secondary$n, c("\u226410", "20"))
  expect_identical(no_secondary$estimate, c("\u226410", "20.5"))
})

test_that("nis_suppress validates data-frame columns and input-specific options", {
  data <- data.frame(n = 4, estimate = 4.5)
  expect_error(nis_suppress(data), "count_col")
  expect_error(nis_suppress(transform(data, n = "4"), count_col = "n"), "numeric")
  expect_error(nis_suppress(data, count_col = "missing"), "not found")
  expect_error(nis_suppress(data, count_col = "n", weighted_cols = "missing"), "not found")
  expect_error(nis_suppress(data, count_col = "n", by = "missing"), "not found")
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
  data <- rbind(make_group("A", 11L, 1L), make_group("B", 11L, 12L))
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
  expect_equal(tiny$stat_0[[1L]], "Masked")
  expect_equal(enc2utf8(tiny$stat_1[[1L]]), "\u226410")
  expect_equal(tiny$stat_2[[1L]], "12 (52%)")
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
  expect_equal(no_by_tiny$stat_0[[1L]], "13 (37%)")
})

test_that("continuous2 statistics use their column nonmissing counts", {
  data <- data.frame(
    age = 31:46,
    group = factor(c(rep("small", 4L), rep("large", 12L)),
      levels = c("small", "large")),
    PSU = 1:16,
    STRATUM = rep(1:2, each = 8L),
    weight = 1
  )
  design <- survey::svydesign(
    ids = ~PSU, strata = ~STRATUM, weights = ~weight, data = data, nest = TRUE
  )
  table <- gtsummary::tbl_svysummary(
    design, by = group, include = age, type = list(age ~ "continuous2"),
    statistic = list(age ~ c("{mean}", "{median}")), missing = "no"
  ) |>
    gtsummary::add_overall()

  suppressed <- nis_suppress(table)
  rows <- which(table$table_body$variable == "age" &
    table$table_body$row_type == "level")
  expect_equal(enc2utf8(suppressed$table_body$stat_1[rows]), rep("\u226410", 2L))
  expect_equal(suppressed$table_body$stat_2[rows], table$table_body$stat_2[rows])
  expect_equal(suppressed$table_body$stat_0[rows], rep("Masked", 2L))
})

test_that("continuous2 suppression errors when displayed counts cannot be verified", {
  data <- data.frame(age = 31:38, PSU = 1:8, weight = 1)
  design <- survey::svydesign(ids = ~PSU, weights = ~weight, data = data)
  table <- gtsummary::tbl_svysummary(
    design, include = age, type = list(age ~ "continuous2"),
    statistic = list(age ~ c("{mean}", "{median}")), missing = "no"
  )
  missing_card <- table
  missing_card$cards$tbl_svysummary <- dplyr::filter(
    missing_card$cards$tbl_svysummary, stat_name != "N_nonmiss_unweighted"
  )
  expect_error(nis_suppress(missing_card), "Cannot verify.*non-missing count")

  duplicate <- table
  card <- dplyr::filter(duplicate$cards$tbl_svysummary,
    stat_name == "N_nonmiss_unweighted")
  duplicate$cards$tbl_svysummary <- dplyr::bind_rows(
    duplicate$cards$tbl_svysummary, card
  )
  expect_error(nis_suppress(duplicate), "Cannot verify.*non-missing count")

  nonfinite <- table
  idx <- which(nonfinite$cards$tbl_svysummary$stat_name ==
    "N_nonmiss_unweighted")[[1L]]
  nonfinite$cards$tbl_svysummary$stat[[idx]] <- Inf
  expect_error(nis_suppress(nonfinite), "Cannot verify.*non-missing count")

  blank <- missing_card
  stat_rows <- which(blank$table_body$variable == "age" &
    blank$table_body$row_type == "level")
  blank$table_body$stat_0[stat_rows] <- NA_character_
  expect_no_warning(nis_suppress(blank))
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

is_masked <- function(cell) identical(enc2utf8(cell), "\u226410")
is_secondary_masked <- function(cell) identical(cell, "Masked")

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
  expect_true(is_secondary_masked(event$stat_0))
  expect_equal(event$stat_2, original$stat_2)

  small <- suppress_row(suppressed, "category", "small")
  expect_true(is_masked(small$stat_1))
  expect_true(is_secondary_masked(small$stat_0))
  expect_false(is_masked(small$stat_2))

  large <- suppress_row(suppressed, "category", "large")
  expect_equal(large$stat_0, suppress_row(table, "category", "large")$stat_0)
  expect_false(any(vapply(large[c("stat_0", "stat_1", "stat_2")], is_masked, logical(1))))

  expect_true(any(grepl(
    "Overall cells in rows with a masked by-group cell",
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
  expect_true(is_secondary_masked(rare$stat_0))
  expect_true(all(vapply(rare[c("stat_1", "stat_2")], is_masked, logical(1))))
  expect_false(is_masked(rare$stat_3))

  other_rare <- suppress_row(table, "other", "rare")
  expect_true(is_masked(other_rare$stat_2))
  expect_true(is_secondary_masked(other_rare$stat_0))
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
  expect_true(is_secondary_masked(small$stat_0))
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
  expect_true(is_secondary_masked(summary_row$stat_0))
  expect_false(is_masked(summary_row$stat_2))

  # B has 50 missing values, A has 92: neither is small, so nothing is masked.
  missing_row <- dplyr::filter(
    table$table_body, variable == "value", row_type == "missing"
  )
  expect_false(any(vapply(missing_row[c("stat_0", "stat_1", "stat_2")], is_masked, logical(1))))
})

test_that("nis_suppress preserves data-frame argument and value validation", {
  data <- data.frame(n = c(4, 20), estimate = c(4.5, 20.5),
    hospitals = c(2, 3), group = c("A", "A"))

  expect_error(nis_suppress(data, count_col = "n", unused = TRUE), "Unused arguments")
  for (threshold in list(-1, NA_real_, Inf, 0.5, "10", c(1, 2))) {
    expect_error(nis_suppress(data, count_col = "n", threshold = threshold),
      "non-negative whole number")
  }
  for (count_col in list(NULL, character(), c("n", "estimate"), NA_character_, "")) {
    expect_error(nis_suppress(data, count_col = count_col), "count_col")
  }
  expect_error(nis_suppress(data, count_col = "n", secondary = NA), "secondary")
  expect_error(nis_suppress(data, count_col = "n", secondary = 1), "secondary")
  expect_error(nis_suppress(data, count_col = "n", weighted_cols = 1), "character vector")
  expect_error(nis_suppress(data, count_col = "n", weighted_cols = NA_character_),
    "character vector")
  expect_error(nis_suppress(data, count_col = "n", by = 1), "character vector")
  expect_error(nis_suppress(data, count_col = "n", hospital_col = c("hospitals", "n")),
    "must name one column")
  expect_error(nis_suppress(data, count_col = "n", hospital_col = "group"), "numeric")

  for (hospital_count in list(NA_real_, Inf, -1, 1.5)) {
    invalid <- data.frame(n = 20, hospitals = hospital_count)
    expect_error(nis_suppress(invalid, count_col = "n", hospital_col = "hospitals"),
      "finite, non-negative whole counts without missing values")
  }
})

test_that("nis_suppress preserves survey-summary input errors and notices", {
  table <- structure(list(cards = list(tbl_svysummary = data.frame())), class = "tbl_svysummary")
  expect_error(nis_suppress(table, count_col = "n"), "apply only to data frames")
  expect_error(nis_suppress(table, weighted_cols = "estimate"), "apply only to data frames")
  expect_error(nis_suppress(table, by = "group"), "apply only to data frames")
  expect_error(nis_suppress(table, hospital_col = "hospitals"), "apply only to data frames")
  expect_error(nis_suppress(table, secondary = FALSE), "applies only to data frames")
  expect_error(nis_suppress(list()), "tbl_svysummary")
})

test_that("data-frame complementary suppression leaves safe strata unchanged", {
  data <- data.frame(n = c(20, 30), estimate = c(20.5, 30.5))
  result <- nis_suppress(data, count_col = "n", weighted_cols = "estimate")
  expect_identical(result$n, c("20", "30"))
  expect_identical(result$estimate, c("20.5", "30.5"))
})

test_that("survey suppression preserves unmatched and unclassified rows", {
  data <- data.frame(category = factor(rep(c("small", "large"), c(4L, 12L))))
  table <- gtsummary::tbl_svysummary(
    suppress_fixture(data), include = category, missing = "no"
  )
  original <- table$table_body
  cards_without_levels <- table
  cards_without_levels$cards$tbl_svysummary$variable_level <- NULL
  without_levels <- nis_suppress(cards_without_levels)
  expect_identical(without_levels$table_body$stat_0, original$stat_0)

  unclassified <- table
  row <- which(unclassified$table_body$row_type == "level")[[1L]]
  unclassified$table_body$row_type[[row]] <- "unclassified"
  unchanged <- nis_suppress(unclassified)
  expect_identical(unchanged$table_body$stat_0[[row]], original$stat_0[[row]])
})

test_that("survey suppression masks an overall cell when its own count is small", {
  data <- data.frame(
    group = factor(rep(c("A", "B"), each = 4L)),
    category = factor(rep(c("small", "large"), 4L), levels = c("small", "large"))
  )
  table <- gtsummary::tbl_svysummary(
    suppress_fixture(data), by = group, include = category, missing = "no"
  ) |>
    gtsummary::add_overall()
  suppressed <- nis_suppress(table)
  small <- dplyr::filter(suppressed$table_body, label == "small")
  expect_identical(enc2utf8(small$stat_0), "\u226410")
})

test_that("nis_suppress validation errors retain the public call", {
  data <- data.frame(n = 1, estimate = 1, group = "A", hospitals = 2)
  threshold_error <- tryCatch(
    nis_suppress(data, count_col = "n", threshold = -1),
    error = identity
  )
  oversized_threshold_error <- tryCatch(
    nis_suppress(data, count_col = "n", threshold = 2147483648),
    error = identity
  )
  missing_count_col_error <- tryCatch(nis_suppress(data), error = identity)
  invalid_count_error <- tryCatch(
    nis_suppress(transform(data, n = -1), count_col = "n"),
    error = identity
  )
  column_errors <- list(
    tryCatch(nis_suppress(data, count_col = "missing"), error = identity),
    tryCatch(nis_suppress(data, count_col = "n", weighted_cols = "missing"),
      error = identity),
    tryCatch(nis_suppress(data, count_col = "n", by = "missing"),
      error = identity),
    tryCatch(nis_suppress(data, count_col = "n", hospital_col = "missing"),
      error = identity)
  )

  expect_identical(rlang::call_name(conditionCall(threshold_error)), "nis_suppress")
  expect_identical(
    rlang::call_name(conditionCall(missing_count_col_error)), "nis_suppress"
  )
  expect_identical(
    rlang::call_name(conditionCall(invalid_count_error)), "nis_suppress"
  )
  expect_match(conditionMessage(oversized_threshold_error), "non-negative whole number")
  expect_identical(
    rlang::call_name(conditionCall(oversized_threshold_error)), "nis_suppress"
  )
  expect_length(column_errors, 4L)
  expect_true(all(vapply(column_errors, function(error) {
    identical(rlang::call_name(conditionCall(error)), "nis_suppress")
  }, logical(1))))
})
