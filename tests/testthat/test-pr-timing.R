test_that("procedure timing evaluates every relation and the earliest index day", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "IX", "IX"),
    I10_PR2 = c("IX", "IX", "IX", "IX", "IX", "IX"),
    I10_PR3 = c("OUT", "OUT", "OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(3L, 3L, 3L, 3L, 3L, 3L),
    PRDAY2 = c(1L, 1L, 1L, 1L, 1L, 1L),
    PRDAY3 = c(2L, 4L, 1L, 1L, 6L, 0L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "on_or_after")$outcome_post_index,
    c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "after")$outcome_post_index,
    c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "before")$outcome_post_index,
    c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "same_day")$outcome_post_index,
    c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_identical(
    nis_flag_pr_timing(data, "ix", "out", relation = "within_days",
      window = 1L)$outcome_post_index,
    c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "ix", "out", relation = "within_days"),
    "window")
  expect_error(nis_flag_pr_timing(data, "ix", "out", window = 1L), "NULL")
  expect_error(nis_flag_pr_timing(data, NA_character_, "out"), "index_pr")
  expect_error(nis_flag_pr_timing(data, "ix", NA_character_), "outcome_pr")
  expect_error(nis_flag_pr_timing(data, "ix", "out-"), "letters and numbers")
})

test_that("procedure timing validation errors retain their public call", {
  data <- dplyr::tibble(I10_PR1 = "IX", I10_PR2 = "OUT", PRDAY1 = 0L,
    PRDAY2 = 1L)
  condition <- tryCatch(
    nis_flag_pr_timing(data, "IX", "OUT", relation = "within_days", window = Inf),
    error = identity
  )

  expect_s3_class(condition, "rlang_error")
  expect_identical(as.character(conditionCall(condition)[[1L]]),
    "nis_flag_pr_timing")
})

test_that("procedure timing accepts integer and mixed numeric day columns", {
  integer_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L), PRDAY2 = c(1L, 1L)
  )
  expect_identical(
    nis_flag_pr_timing(integer_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )

  mixed_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L), PRDAY2 = c(1, 1)
  )
  expect_identical(
    nis_flag_pr_timing(mixed_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )
})

test_that("procedure timing treats an unmatched PRDAY slot as unknown", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"), I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "IX", "OUT")$outcome_post_index,
    c(FALSE, FALSE)
  )
})

test_that("procedure timing matches the documented four-row example", {
  data <- dplyr::tibble(
    I10_PR1 = rep("02UG0JZ", 4L),
    PRDAY1 = c(0L, 2L, 3L, -99L),
    I10_PR2 = rep("0JH604Z", 4L),
    PRDAY2 = c(1L, 1L, 3L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "02UG0", "0JH60")$outcome_post_index,
    c(TRUE, FALSE, TRUE, FALSE)
  )
})

test_that("procedure timing handles missing days and absent procedures", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "OTHER", "IX"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT", "OUT", "OTHER"),
    PRDAY1 = c(-99L, NA_integer_, 0L, -99L, 1L, 0L),
    PRDAY2 = c(1L, 1L, -88L, -66L, 2L, 1L)
  )
  for (policy in c("exclude", "assume_same_day", "indeterminate")) {
    actual <- nis_flag_pr_timing(data, "IX", "OUT", missing_day = policy)$outcome_post_index
    expected <- switch(policy,
      exclude = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
      assume_same_day = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
      indeterminate = c(NA, NA, NA, NA, FALSE, FALSE)
    )
    expect_identical(actual, expected)
  }
  # A determinate satisfying pair wins even if another matching slot is unknown.
  mixed <- dplyr::tibble(I10_PR1 = "IX", I10_PR2 = c("IX", "OUT"),
    I10_PR3 = c("OUT", "IX"), PRDAY1 = c(-99L, 0L),
    PRDAY2 = c(0L, 0L), PRDAY3 = c(0L, -99L))
  expect_identical(
    nis_flag_pr_timing(mixed, "IX", "OUT", missing_day = "indeterminate")$outcome_post_index,
    c(TRUE, TRUE)
  )
})

test_that("procedure timing policies have explicit relation expectations", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "IX", "IX"),
    I10_PR2 = c("OTHER", "OTHER", "IX", "OTHER", "OTHER"),
    I10_PR3 = rep("OUT", 5L),
    PRDAY1 = c(5L, -99L, -99L, 5L, 5L),
    PRDAY2 = c(1L, 1L, 5L, 1L, 1L),
    PRDAY3 = c(NA_real_, 0, 4, 3, 5)
  )
  expected <- list(
    exclude = list(
      on_or_after = c(FALSE, FALSE, FALSE, FALSE, TRUE),
      after = c(FALSE, FALSE, FALSE, FALSE, FALSE),
      before = c(FALSE, FALSE, TRUE, TRUE, FALSE),
      same_day = c(FALSE, FALSE, FALSE, FALSE, TRUE),
      within_days = c(FALSE, FALSE, FALSE, FALSE, TRUE)
    ),
    assume_same_day = list(
      on_or_after = c(FALSE, TRUE, TRUE, FALSE, TRUE),
      after = c(FALSE, FALSE, TRUE, FALSE, FALSE),
      before = c(TRUE, FALSE, FALSE, TRUE, FALSE),
      same_day = c(FALSE, TRUE, FALSE, FALSE, TRUE),
      within_days = c(FALSE, TRUE, FALSE, FALSE, TRUE)
    ),
    indeterminate = list(
      on_or_after = c(NA, NA, NA, FALSE, TRUE),
      after = c(NA, NA, NA, FALSE, FALSE),
      before = c(NA, NA, TRUE, TRUE, FALSE),
      same_day = c(NA, NA, NA, FALSE, TRUE),
      within_days = c(NA, NA, NA, FALSE, TRUE)
    )
  )
  for (policy in names(expected)) {
    for (relation in names(expected[[policy]])) {
      window <- if (relation == "within_days") 1L else NULL
      expect_identical(
        nis_flag_pr_timing(data, "IX", "OUT", relation = relation,
          window = window, missing_day = policy)$outcome_post_index,
        expected[[policy]][[relation]],
        info = paste(policy, relation)
      )
    }
  }
})

test_that("procedure timing uses ICD-9 slots and validates its output", {
  data <- dplyr::tibble(
    PR1 = c("3722", "3722"), PR2 = c("3325", "3325"),
    PRDAY1 = c(1L, 3L), PRDAY2 = c(2L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "37.2", "33 25", system = "icd9")$outcome_post_index,
    c(TRUE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "37", "33", name = "PR1"),
    "must not replace")
  expect_error(nis_flag_pr_timing(dplyr::select(data, -PRDAY1, -PRDAY2),
    "37", "33", system = "icd9"), "PRDAY")
  expect_error(nis_flag_pr_timing(data, "37", "33", name = c("x", "y")),
    "single")
})

test_that("procedure timing stays lazy and agrees with data frames on DuckDB", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "OTHER"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(0L, 2L, -99L, 1L), PRDAY2 = c(1L, 1L, 1L, 2L)
  )
  path <- tempfile("nis-pr-timing-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)
  expected <- nis_flag_pr_timing(data, "IX", "OUT")
  lazy <- nis_flag_pr_timing(query, "IX", "OUT")
  expect_s3_class(lazy, "tbl_sql")
  expect_identical(dplyr::collect(lazy), expected)
})

test_that("procedure timing agrees across DuckDB policies and many slots", {
  procedure_slots <- stats::setNames(rep(list(rep("OTHER", 5L)), 25L),
    paste0("I10_PR", seq_len(25L)))
  procedure_slots[[1L]] <- c("IX", "IX", "IX", "IX", "IX")
  procedure_slots[[2L]] <- c("OUT", "OUT", "OUT", "OUT", "OUT")
  procedure_slots[[3L]] <- c("IDX", "IDX", "OTHER", "OTHER", "OTHER")
  procedure_slots[[4L]] <- c("ALT", "ALT", "ALT", "ALT", "ALT")
  procedure_slots[[12L]] <- c("OUT", "OUT", "OUT", "OUT", "OUT")
  day_slots <- stats::setNames(rep(list(rep(1L, 5L)), 11L),
    paste0("PRDAY", seq_len(11L)))
  day_slots[[1L]] <- c(0L, -99L, 0L, -99L, -99L)
  day_slots[[2L]] <- c(1, 1, -99, NA_real_, 1)
  day_slots[[3L]] <- c(2L, 1L, 0L, -99L, 1L)
  day_slots[[4L]] <- c(3L, -99L, 0L, 1L, 1L)
  data <- dplyr::as_tibble(c(procedure_slots, day_slots, list(
    YEAR = rep(2018L, 5L), PRVER = c(10L, 10L, 10L, 10L, 9L)
  )))
  path <- tempfile("nis-pr-timing-many-slots-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)

  small_data <- dplyr::select(data, I10_PR1:I10_PR4, PRDAY1:PRDAY4, YEAR, PRVER)
  small_query <- duckdb_query_fixture(small_data)
  query_data <- list(list(data, query), list(small_data, small_query))
  for (i in seq_along(query_data)) {
    cases <- if (i == 1L) {
      list(c("exclude", "on_or_after"), c("indeterminate", "on_or_after"),
        c("indeterminate", "within_days"))
    } else {
      grid <- expand.grid(
        policy = c("exclude", "assume_same_day", "indeterminate"),
        relation = c("on_or_after", "after", "before", "same_day", "within_days"),
        stringsAsFactors = FALSE
      )
      lapply(seq_len(nrow(grid)), function(row) {
        unname(unlist(grid[row, ], use.names = FALSE))
      })
    }
    for (case in cases) {
      policy <- case[[1L]]
      relation <- case[[2L]]
      window <- if (relation == "within_days") 2L else NULL
      expected <- nis_flag_pr_timing(query_data[[i]][[1L]], c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
        relation = relation, window = window, missing_day = policy)
      actual <- nis_flag_pr_timing(query_data[[i]][[2L]], c("IX", "IDX", "NOMATCH"), c("OUT", "ALT"),
        relation = relation, window = window, missing_day = policy) |>
        dplyr::collect()
      expect_identical(actual, expected)
    }
  }
})

test_that("PRDAY completeness counts matching slots by year and slot", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L),
    I10_PR1 = c("IX", "IX", "IX", "OTHER"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(0L, -99L, 0L, 0L),
    PRDAY2 = c(0L, NA_integer_, -88L, 1L)
  )
  actual <- nis_prday_completeness(data, c("ix", "out"))
  expect_identical(actual, dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L), slot = c(1L, 2L, 1L, 2L),
    matched_slots = c(2L, 2L, 1L, 2L), known_day = c(1L, 1L, 1L, 1L),
    missing_day = c(0L, 1L, 0L, 0L),
    sentinel_invalid_day = c(1L, 0L, 0L, 1L),
    absent_prday_column = c(0L, 0L, 0L, 0L), pct_known = c(50, 50, 100, 50)
  ))

  no_slot_day <- dplyr::select(data, -PRDAY2)
  absent <- nis_prday_completeness(no_slot_day, "out")
  absent_slot2 <- dplyr::filter(absent, slot == 2L)
  expect_identical(absent_slot2$absent_prday_column, c(2L, 2L))
  expect_identical(absent_slot2$matched_slots, c(2L, 2L))

  duckdb_result <- nis_prday_completeness(duckdb_query_fixture(data),
    c("ix", "out"))
  expect_equal(duckdb_result, actual)
})

test_that("PRDAY completeness aggregates on DuckDB queries", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  data <- dplyr::tibble(YEAR = c(2020L, 2020L), I10_PR1 = c("IX", "IX"),
    PRDAY1 = c(0L, -99L))
  con <- duckdb::dbConnect(duckdb::duckdb())
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  query <- dplyr::tbl(con, "fixture")
  result <- nis_prday_completeness(query, "IX")
  expect_equal(result$matched_slots, 2L)
  expect_equal(result$known_day, 1L)
  expect_equal(result$sentinel_invalid_day, 1L)
})

test_that("PRDAY completeness matches the prior per-slot result for three slots", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L),
    I10_PR1 = c("IX", "OTHER", "IX", "IX"),
    I10_PR2 = c("OTHER", "IX", "IX", "IX"),
    I10_PR3 = c("IX", "IX", "OTHER", "IX"),
    PRDAY1 = c(0L, 1L, -99L, NA_integer_),
    PRDAY2 = c(NA_integer_, 0L, 1L, -88L),
    PRDAY3 = c(-99L, 0L, 1L, 2L)
  )
  prefixes <- "IX"
  previous_per_slot <- lapply(seq_len(3L), function(slot) {
    procedure <- data[[paste0("I10_PR", slot)]]
    day <- data[[paste0("PRDAY", slot)]]
    matched <- !is.na(procedure) & startsWith(procedure, prefixes)
    data |>
      dplyr::mutate(
        matched = matched,
        known = matched & !is.na(day) & day >= 0,
        missing = matched & is.na(day),
        invalid = matched & !is.na(day) & day < 0
      ) |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(
        matched_slots = sum(as.integer(matched), na.rm = TRUE),
        known_day = sum(as.integer(known), na.rm = TRUE),
        missing_day = sum(as.integer(missing), na.rm = TRUE),
        sentinel_invalid_day = sum(as.integer(invalid), na.rm = TRUE),
        absent_prday_column = 0L,
        .groups = "drop"
      ) |>
      dplyr::mutate(slot = as.integer(slot), .before = 1L)
  }) |>
    dplyr::bind_rows() |>
    dplyr::mutate(pct_known = dplyr::if_else(matched_slots == 0L, NA_real_,
      100 * known_day / matched_slots)) |>
    dplyr::select(YEAR, slot, matched_slots, known_day, missing_day,
      sentinel_invalid_day, absent_prday_column, pct_known) |>
    dplyr::arrange(YEAR, slot)

  expect_identical(nis_prday_completeness(data, prefixes), previous_per_slot)
})

test_that("PRDAY completeness classifies days like procedure timing", {
  data <- dplyr::tibble(
    YEAR = rep(2020L, 4L),
    I10_PR1 = rep("IX", 4L), I10_PR2 = rep("OUT", 4L),
    PRDAY1 = rep(0L, 4L), PRDAY2 = c(0L, 1L, NA_integer_, -99L)
  )
  summary <- nis_prday_completeness(data, "OUT")
  flag <- nis_flag_pr_timing(data, "IX", "OUT", relation = "same_day",
    missing_day = "indeterminate")$outcome_post_index
  expect_identical(flag, c(TRUE, FALSE, NA, NA))
  expect_identical(summary$known_day[summary$slot == 2L],
    as.integer(sum(!is.na(flag))))
  expect_identical(summary$missing_day[summary$slot == 2L],
    as.integer(sum(is.na(data$PRDAY2))))
  expect_identical(summary$sentinel_invalid_day[summary$slot == 2L], 1L)
})

test_that("PRDAY NaN, infinities, sentinels, and missing values match frames", {
  data <- dplyr::tibble(
    YEAR = rep(2020L, 5L),
    I10_PR1 = rep("IX", 5L), I10_PR2 = rep("OUT", 5L),
    PRDAY1 = rep(0, 5L), PRDAY2 = c(0, -99, NA_real_, NaN, Inf)
  )
  query <- duckdb_query_fixture(data)
  on.exit({
    con <- query$src$con
    query <- NULL
    invisible(gc())
    if (duckdb::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }, add = TRUE)

  for (policy in c("exclude", "assume_same_day", "indeterminate")) {
    for (relation in c("on_or_after", "after", "before", "same_day", "within_days")) {
      expected <- nis_flag_pr_timing(data, "IX", "OUT", relation = relation,
        window = if (relation == "within_days") 2L else NULL,
        missing_day = policy)
      actual <- nis_flag_pr_timing(query, "IX", "OUT", relation = relation,
        window = if (relation == "within_days") 2L else NULL,
        missing_day = policy) |>
        dplyr::collect()
      expect_identical(actual, expected, info = paste(policy, relation))
    }
  }
  expect_identical(nis_prday_completeness(query, "OUT"),
    nis_prday_completeness(data, "OUT"))
})

test_that("PRDAY missing checks support logical, character, and numeric columns", {
  day_values <- list(
    logical = NA,
    character = NA_character_,
    numeric = NA_real_
  )
  for (day_type in names(day_values)) {
    data <- dplyr::tibble(
      YEAR = 2020L, I10_PR1 = "IX", I10_PR2 = "OUT",
      PRDAY1 = 0L, PRDAY2 = day_values[[day_type]]
    )
    expected <- nis_flag_pr_timing(data, "IX", "OUT",
      relation = "same_day", missing_day = "indeterminate")
    query <- duckdb_query_fixture(data)
    actual <- nis_flag_pr_timing(query, "IX", "OUT",
      relation = "same_day", missing_day = "indeterminate") |>
      dplyr::collect()
    expect_identical(actual, expected, info = day_type)
    expect_identical(nis_prday_completeness(query, "OUT"),
      nis_prday_completeness(data, "OUT"), info = day_type)
    con <- query$src$con
    query <- NULL
    invisible(gc())
    if (duckdb::dbIsValid(con)) DBI::dbDisconnect(con, shutdown = TRUE)
  }
})
