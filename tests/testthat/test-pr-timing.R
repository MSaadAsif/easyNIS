test_that("procedure timing system help renders its slot description as HTML", {
  rd_file <- test_path("..", "..", "man", "nis_flag_pr_timing.Rd")
  rd <- if (file.exists(rd_file)) {
    tools::parse_Rd(rd_file)
  } else {
    tools::Rd_db("easyNIS")[["nis_flag_pr_timing.Rd"]]
  }
  expect_false(is.null(rd))

  html_path <- tempfile(fileext = ".html")
  on.exit(unlink(html_path), add = TRUE)
  tools::Rd2HTML(rd, out = html_path)
  html <- paste(readLines(html_path, warn = FALSE), collapse = "\n")

  expect_false(grepl("<n>", html, fixed = TRUE))
  expect_match(html, "slot number", fixed = TRUE)
})

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
    nis_flag_pr_timing(data, "ix", "out", relation = "within_days", window = 1L)$outcome_post_index,
    c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "ix", "out", relation = "within_days"), "window")
  expect_error(nis_flag_pr_timing(data, "ix", "out", window = 1L), "NULL")
  expect_error(nis_flag_pr_timing(data, NA_character_, "out"), "index_pr")
  expect_error(nis_flag_pr_timing(data, "ix", NA_character_), "outcome_pr")
  expect_error(nis_flag_pr_timing(data, "ix", "out-"), "letters and numbers")
})

test_that("procedure timing validation errors retain their public call", {
  data <- dplyr::tibble(I10_PR1 = "IX", I10_PR2 = "OUT", PRDAY1 = 0L, PRDAY2 = 1L)
  condition <- tryCatch(
    nis_flag_pr_timing(data, "IX", "OUT", relation = "within_days", window = Inf),
    error = identity
  )

  expect_s3_class(condition, "rlang_error")
  expect_identical(
    conditionCall(condition),
    quote(nis_flag_pr_timing(data, "IX", "OUT", relation = "within_days", window = Inf))
  )
})

test_that("whole numeric timing windows include the boundary in DuckDB", {
  data <- dplyr::tibble(id = 1:2, I10_PR1 = "IX", I10_PR2 = "OUT", PRDAY1 = 0L, PRDAY2 = c(2L, 3L))
  actual <- nis_flag_pr_timing(duckdb_query_fixture(data), "IX", "OUT", relation = "within_days", window = 2.0) |>
    dplyr::arrange(id) |>
    dplyr::collect()
  expect_identical(actual$outcome_post_index, c(TRUE, FALSE))
})

test_that("procedure timing accepts integer and mixed numeric day columns", {
  integer_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"),
    I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L),
    PRDAY2 = c(1L, 1L)
  )
  expect_identical(
    nis_flag_pr_timing(integer_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )

  mixed_days <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"),
    I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L),
    PRDAY2 = c(1, 1)
  )
  expect_identical(
    nis_flag_pr_timing(mixed_days, "IX", "OUT")$outcome_post_index,
    c(TRUE, FALSE)
  )
})

test_that("procedure timing treats an unmatched PRDAY slot as unknown", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX"),
    I10_PR2 = c("OUT", "OUT"),
    PRDAY1 = c(0L, 2L)
  )
  for (input in list(data, duckdb_query_fixture(data))) {
    excluded <- nis_flag_pr_timing(input, "IX", "OUT") |> dplyr::collect()
    expect_identical(excluded$outcome_post_index, c(FALSE, FALSE))
    unknown <- nis_flag_pr_timing(input, "IX", "OUT", missing_day = "indeterminate") |> dplyr::collect()
    expect_identical(unknown$outcome_post_index, c(NA, NA))
  }
})

test_that("procedure timing pairs and orders two-digit slots by number", {
  data <- dplyr::tibble(
    YEAR = 2020L,
    I10_PR12 = "OUT",
    I10_PR10 = "OUT",
    I10_PR2 = "IX",
    PRDAY10 = c(2L, 0L),
    PRDAY2 = 1L
  )
  for (input in list(data, duckdb_query_fixture(data))) {
    result <- nis_flag_pr_timing(input, "IX", "OUT", missing_day = "indeterminate") |>
      dplyr::collect()
    expect_identical(result$outcome_post_index, c(TRUE, NA))
    completion <- nis_audit_prday(input, "OUT")
    expect_identical(completion$slot, c(2L, 10L, 12L))
    expect_identical(completion$known_day, c(0L, 2L, 0L))
    expect_identical(completion$absent_prday_column, c(0L, 0L, 2L))
  }
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
    expected <- switch(
      policy,
      exclude = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
      assume_same_day = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
      indeterminate = c(NA, NA, NA, NA, FALSE, FALSE)
    )
    expect_identical(actual, expected)
  }
  # A determinate satisfying pair wins even if another matching slot is unknown.
  mixed <- dplyr::tibble(
    I10_PR1 = "IX",
    I10_PR2 = c("IX", "OUT"),
    I10_PR3 = c("OUT", "IX"),
    PRDAY1 = c(-99L, 0L),
    PRDAY2 = c(0L, 0L),
    PRDAY3 = c(0L, -99L)
  )
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
        nis_flag_pr_timing(
          data,
          "IX",
          "OUT",
          relation = relation,
          window = window,
          missing_day = policy
        )$outcome_post_index,
        expected[[policy]][[relation]],
        info = paste(policy, relation)
      )
    }
  }
})

test_that("procedure timing uses ICD-9 slots and validates its output", {
  data <- dplyr::tibble(
    PR1 = c("3722", "3722"),
    PR2 = c("3325", "3325"),
    PRDAY1 = c(1L, 3L),
    PRDAY2 = c(2L, 2L)
  )
  expect_identical(
    nis_flag_pr_timing(data, "37.2", "33 25", system = "icd9")$outcome_post_index,
    c(TRUE, FALSE)
  )
  expect_error(nis_flag_pr_timing(data, "37", "33", name = "PR1"), "must not replace")
  expect_error(nis_flag_pr_timing(dplyr::select(data, -PRDAY1, -PRDAY2), "37", "33", system = "icd9"), "PRDAY")
  expect_error(nis_flag_pr_timing(data, "37", "33", name = c("x", "y")), "single")
})

test_that("procedure timing stays lazy and agrees with data frames on DuckDB", {
  data <- dplyr::tibble(
    I10_PR1 = c("IX", "IX", "IX", "OTHER"),
    I10_PR2 = c("OUT", "OUT", "OUT", "OUT"),
    PRDAY1 = c(0L, 2L, -99L, 1L),
    PRDAY2 = c(1L, 1L, 1L, 2L)
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

test_that("procedure timing can outlive and compose with its grouped source", {
  root <- withr::local_tempdir()
  frame <- dplyr::tibble(
    YEAR = 2020L,
    id = 1:3,
    I10_PR1 = "IX",
    I10_PR2 = "OUT",
    PRDAY1 = 0L,
    PRDAY2 = c(2L, 1L, 0L),
    .nis_timing_day_1 = 42L
  )
  write_duckdb_parquet(frame, file.path(root, "NIS_2020.parquet"))
  flagged <- local({
    source <- nis_open(root, check_release = FALSE) |>
      dplyr::filter(id > 1L) |>
      dplyr::group_by(YEAR) |>
      dplyr::arrange(dplyr::desc(id))
    nis_flag_pr_timing(source, "IX", "OUT", name = 'a "flag"', relation = "after")
  })
  invisible(gc())
  expect_s3_class(flagged, "tbl_nis")
  expect_identical(dplyr::group_vars(flagged), "YEAR")
  collected <- flagged |>
    dplyr::mutate(sequence = dplyr::row_number()) |>
    dplyr::collect()
  expect_identical(collected$id, c(3L, 2L))
  expect_equal(collected$sequence, 1:2)
  expect_identical(collected[['a "flag"']], c(FALSE, TRUE))
  expect_identical(collected$.nis_timing_day_1, c(42L, 42L))
})

test_that("procedure timing agrees across DuckDB policies and relations", {
  data <- pr_timing_parity_data()
  query <- duckdb_query_fixture(data)
  for (policy in c("exclude", "assume_same_day", "indeterminate")) {
    for (relation in c("on_or_after", "after", "before", "same_day", "within_days")) {
      window <- if (relation == "within_days") 2L else NULL
      expected <- nis_flag_pr_timing(
        data,
        c("IX", "IDX", "NOMATCH"),
        c("OUT", "ALT"),
        relation = relation,
        window = window,
        missing_day = policy
      )
      actual <- nis_flag_pr_timing(
        query,
        c("IX", "IDX", "NOMATCH"),
        c("OUT", "ALT"),
        relation = relation,
        window = window,
        missing_day = policy
      ) |>
        dplyr::collect()
      expect_identical(actual, expected, info = paste(policy, relation))
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
  actual <- nis_audit_prday(data, c("ix", "out"))
  expect_identical(
    actual,
    dplyr::tibble(
      YEAR = c(2020L, 2020L, 2021L, 2021L),
      slot = c(1L, 2L, 1L, 2L),
      matched_slots = c(2L, 2L, 1L, 2L),
      known_day = c(1L, 1L, 1L, 1L),
      missing_day = c(0L, 1L, 0L, 0L),
      sentinel_invalid_day = c(1L, 0L, 0L, 1L),
      absent_prday_column = c(0L, 0L, 0L, 0L),
      pct_known = c(50, 50, 100, 50)
    )
  )

  no_slot_day <- dplyr::select(data, -PRDAY2)
  absent <- nis_audit_prday(no_slot_day, "out")
  absent_slot2 <- dplyr::filter(absent, slot == 2L)
  expect_identical(absent_slot2$absent_prday_column, c(2L, 2L))
  expect_identical(absent_slot2$matched_slots, c(2L, 2L))

  duckdb_result <- nis_audit_prday(duckdb_query_fixture(data), c("ix", "out"))
  expect_equal(duckdb_result, actual)
})

test_that("PRDAY completeness aggregates on DuckDB queries", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  data <- dplyr::tibble(YEAR = c(2020L, 2020L), I10_PR1 = c("IX", "IX"), PRDAY1 = c(0L, -99L))
  con <- duckdb::dbConnect(duckdb::duckdb())
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "fixture", data, temporary = TRUE)
  query <- dplyr::tbl(con, "fixture")
  result <- nis_audit_prday(query, "IX")
  expect_equal(result$matched_slots, 2L)
  expect_equal(result$known_day, 1L)
  expect_equal(result$sentinel_invalid_day, 1L)
})

test_that("PRDAY completeness separates matches by year and slot", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2021L, 2021L),
    I10_PR1 = c("IX", "OTHER", "IX", "IX"),
    I10_PR2 = c("OTHER", "IX", "IX", "IX"),
    I10_PR3 = c("IX", "IX", "OTHER", "IX"),
    PRDAY1 = c(0L, 1L, -99L, NA_integer_),
    PRDAY2 = c(NA_integer_, 0L, 1L, -88L),
    PRDAY3 = c(-99L, 0L, 1L, 2L)
  )
  expected <- dplyr::tibble(
    YEAR = rep(2020:2021, each = 3L),
    slot = rep(1:3, 2),
    matched_slots = c(1L, 1L, 2L, 2L, 2L, 1L),
    known_day = c(1L, 1L, 1L, 0L, 1L, 1L),
    missing_day = c(0L, 0L, 0L, 1L, 0L, 0L),
    sentinel_invalid_day = c(0L, 0L, 1L, 1L, 1L, 0L),
    absent_prday_column = rep(0L, 6L),
    pct_known = c(100, 100, 50, 0, 50, 100)
  )
  expect_identical(nis_audit_prday(data, "IX"), expected)
})

test_that("PRDAY completeness classifies days like procedure timing", {
  data <- dplyr::tibble(
    YEAR = rep(2020L, 4L),
    I10_PR1 = rep("IX", 4L),
    I10_PR2 = rep("OUT", 4L),
    PRDAY1 = rep(0L, 4L),
    PRDAY2 = c(0L, 1L, NA_integer_, -99L)
  )
  summary <- nis_audit_prday(data, "OUT")
  flag <- nis_flag_pr_timing(data, "IX", "OUT", relation = "same_day", missing_day = "indeterminate")$outcome_post_index
  expect_identical(flag, c(TRUE, FALSE, NA, NA))
  expect_identical(summary$known_day[summary$slot == 2L], as.integer(sum(!is.na(flag))))
  expect_identical(summary$missing_day[summary$slot == 2L], as.integer(sum(is.na(data$PRDAY2))))
  expect_identical(summary$sentinel_invalid_day[summary$slot == 2L], 1L)
})

test_that("PRDAY completeness uses factor labels across input types", {
  values <- c("-1", "999", NA_character_, "1")
  data <- dplyr::tibble(
    YEAR = rep(2020L, length(values)),
    I10_PR1 = rep("OUT", length(values)),
    PRDAY1 = factor(values, levels = c("", "-1", "1", "999", "unused"))
  )
  expected <- nis_audit_prday(data, "OUT")
  expect_identical(expected$known_day, 2L)
  expect_identical(expected$missing_day, 1L)
  expect_identical(expected$sentinel_invalid_day, 1L)

  for (input in list(
    character = dplyr::mutate(data, PRDAY1 = values),
    numeric = dplyr::mutate(data, PRDAY1 = c(-1, 999, NA_real_, 1))
  )) {
    expect_identical(nis_audit_prday(input, "OUT"), expected)
  }

  query <- duckdb_query_fixture(data)
  expect_identical(nis_audit_prday(query, "OUT"), expected)
})

test_that("PRDAY completeness buckets unparseable and NaN text days as missing", {
  values <- c("0", "-1", "", "abc", "NaN", NA_character_)
  data <- dplyr::tibble(
    YEAR = rep(2020L, length(values)),
    I10_PR1 = rep("OUT", length(values)),
    PRDAY1 = values
  )
  # Unparseable text days coerce to NA with a base R warning, as in
  # nis_flag_pr_timing().
  expected <- suppressWarnings(nis_audit_prday(data, "OUT"))
  expect_identical(expected$known_day, 1L)
  expect_identical(expected$sentinel_invalid_day, 1L)
  expect_identical(expected$missing_day, 4L)
  expect_identical(
    expected$known_day + expected$missing_day + expected$sentinel_invalid_day,
    expected$matched_slots
  )

  levels <- c("", "-1", "0", "NaN", "abc", "unused")
  factor_data <- dplyr::mutate(data, PRDAY1 = factor(values, levels = levels))
  expect_identical(
    suppressWarnings(nis_audit_prday(factor_data, "OUT")),
    expected
  )

  query <- duckdb_query_fixture(data)
  expect_identical(nis_audit_prday(query, "OUT"), expected)
})

test_that("PRDAY NaN, infinities, sentinels, and missing values match frames", {
  data <- dplyr::tibble(
    YEAR = rep(2020L, 5L),
    I10_PR1 = rep("IX", 5L),
    I10_PR2 = rep("OUT", 5L),
    PRDAY1 = rep(0, 5L),
    PRDAY2 = c(0, -99, NA_real_, NaN, Inf)
  )
  query <- duckdb_query_fixture(data)

  for (policy in c("exclude", "assume_same_day", "indeterminate")) {
    for (relation in c("on_or_after", "after", "before", "same_day", "within_days")) {
      expected <- nis_flag_pr_timing(
        data,
        "IX",
        "OUT",
        relation = relation,
        window = if (relation == "within_days") 2L else NULL,
        missing_day = policy
      )
      actual <- nis_flag_pr_timing(
        query,
        "IX",
        "OUT",
        relation = relation,
        window = if (relation == "within_days") 2L else NULL,
        missing_day = policy
      ) |>
        dplyr::collect()
      expect_identical(actual, expected, info = paste(policy, relation))
    }
  }
  expect_identical(nis_audit_prday(query, "OUT"), nis_audit_prday(data, "OUT"))
})

test_that("PRDAY missing checks support logical, character, and numeric columns", {
  day_values <- list(
    logical = NA,
    character = NA_character_,
    numeric = NA_real_
  )
  for (day_type in names(day_values)) {
    data <- dplyr::tibble(
      YEAR = 2020L,
      I10_PR1 = "IX",
      I10_PR2 = "OUT",
      PRDAY1 = 0L,
      PRDAY2 = day_values[[day_type]]
    )
    expected <- nis_flag_pr_timing(data, "IX", "OUT", relation = "same_day", missing_day = "indeterminate")
    query <- duckdb_query_fixture(data)
    actual <- nis_flag_pr_timing(query, "IX", "OUT", relation = "same_day", missing_day = "indeterminate") |>
      dplyr::collect()
    expect_identical(actual, expected, info = day_type)
    expect_identical(nis_audit_prday(query, "OUT"), nis_audit_prday(data, "OUT"), info = day_type)
  }
})


test_that("procedure timing preserves requested flags with equivalent slot names", {
  frame <- dplyr::tibble(
    YEAR = 2020L,
    I10_PR1 = "IX",
    I10_PR2 = "OUT",
    I10_PR01 = "OUT",
    PRDAY01 = 15L,
    PRDAY1 = 0L,
    PRDAY2 = 5L
  )
  output <- ".easyNIS_pr_timing_match_1"
  for (data in list(frame, duckdb_query_fixture(frame))) {
    for (display_name in list(stats::setNames(output, "requested"), I(output))) {
      result <- nis_flag_pr_timing(data, "IX", "OUT", name = display_name)
      collected <- dplyr::collect(result)
      expect_identical(collected[[output]], TRUE)
      expect_identical(names(collected), c(names(frame), output))
    }
    expect_identical(nis_audit_prday(data, "OUT")$matched_slots, c(0L, 1L, 1L))
  }
})

test_that("empty PRDAY summaries retain the yearly output schema", {
  frame <- dplyr::tibble(YEAR = integer(), I10_PR1 = character(), PRDAY1 = integer())
  expected <- dplyr::tibble(
    YEAR = integer(),
    slot = integer(),
    matched_slots = integer(),
    known_day = integer(),
    missing_day = integer(),
    sentinel_invalid_day = integer(),
    absent_prday_column = integer(),
    pct_known = double()
  )
  expect_identical(nis_audit_prday(frame, "IX"), expected)
  expect_identical(nis_audit_prday(duckdb_query_fixture(frame), "IX"), expected)
})
test_that("procedure timing and completeness preserve numeric slot pairing", {
  frame <- dplyr::tibble(YEAR = 2020L, I10_PR01 = "IX", I10_PR2 = "OUT", PRDAY1 = 0L, PRDAY01 = 9L, PRDAY2 = 5L)
  reversed <- dplyr::relocate(frame, PRDAY01, .before = PRDAY1)
  padded_day <- dplyr::rename(dplyr::select(frame, -PRDAY01), I10_PR1 = I10_PR01, PRDAY01 = PRDAY1)
  legacy <- dplyr::tibble(YEAR = 2014L, PR0 = "0123", PR1 = "9999", PRDAY00 = 0L, PRDAY1 = 1L)
  for (copier in list(identity, duckdb_query_fixture)) {
    timing <- function(data) {
      dplyr::collect(nis_flag_pr_timing(copier(data), "IX", "OUT", name = "after"))$after
    }
    expect_true(timing(frame))
    expect_false(timing(reversed))
    expect_true(timing(padded_day))
    completion <- nis_audit_prday(copier(legacy), "0123", system = "icd9")
    expect_identical(completion$slot, 0:1)
    expect_identical(completion$known_day, c(1L, 0L))
    expect_error(nis_flag_pr(copier(frame), matched = "IX", position = "principal"), "No ICD-10")
  }
})

test_that("mixed-year procedure timing keeps code rules and days within each system", {
  root <- withr::local_tempdir()
  data <- dplyr::tibble(
    ID = 1:6,
    YEAR = 2015L,
    DQTR = c(3L, 4L, 4L, 3L, 4L, NA_integer_),
    PRVER = c(9L, 10L, 10L, 10L, 10L, NA_integer_),
    PR1 = c("371", NA, NA, "371", NA, "371"),
    PR2 = c("330", NA, NA, "330", NA, NA),
    I10_PR1 = c(NA, "IXBAD", "IXBAD", "IXBAD", "ALT", NA),
    I10_PR2 = c(NA, "IX", "IX", "IX", "OUT7", "OUT7"),
    I10_PR3 = c(NA, "OUT7", "OUT70", "OUT7", NA, NA),
    PRDAY1 = c(0L, 0L, 0L, 0L, 0L, 0L),
    PRDAY2 = c(1L, 3L, 3L, 3L, -99L, 1L),
    PRDAY3 = c(1L, 1L, 4L, 4L, 1L, 1L)
  )
  write_duckdb_parquet(data, file.path(root, "NIS_2015.parquet"))
  query <- suppressMessages(nis_open(root, check_release = FALSE))
  for (input in list(data, query)) {
    result <- input |>
      nis_flag_pr_timing(
        index_pr = list(icd9 = "37", icd10 = list(prefix = c("IX", "ALT"), exclude = "IXBAD")),
        outcome_pr = list(icd9 = "33", icd10 = list(regex = "OUT[0-9]")),
        relation = "after",
        missing_day = "indeterminate",
        system = "both"
      ) |>
      dplyr::arrange(ID) |>
      dplyr::collect()
    expect_identical(result$outcome_post_index, c(TRUE, FALSE, FALSE, FALSE, NA, FALSE))
  }
})
