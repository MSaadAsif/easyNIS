test_that("code transition audit completes the period and code-group grid", {
  data <- dplyr::tibble(
    YEAR = c(2018L, 2018L, 2019L, 2019L, 2020L, 2020L),
    I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0JZ", "02803ZZ", "02803ZZ", "02803ZZ"),
    I10_PR2 = c("02UG0JZ", NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
    DISCWT = c(5, 7, 5, 3, 4, 6),
    AGE = c(40L, 17L, 60L, 50L, 70L, 45L)
  )
  result <- nis_audit_code_transition(data,
    codes = c(myectomy = "02UG0JZ", ablation = "02803ZZ"))

  expect_named(result, c("YEAR", "code_group", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "pct_within_year", "yoy_pct_change"))
  expect_equal(nrow(result), 6L)
  expect_equal(result$code_group,
    c(rep("myectomy", 3), rep("ablation", 3)))
  expect_equal(result$n_cohort_unweighted, rep(2L, 6))
  expect_equal(result$n_unweighted, c(2L, 1L, 0L, 0L, 1L, 2L))
  expect_equal(result$n_weighted, c(12, 5, 0, 0, 3, 10))
  expect_equal(result$pct_within_year, c(100, 50, 0, 0, 50, 100))
  expect_true(is.na(result$yoy_pct_change[[1L]]))
  expect_equal(result$yoy_pct_change[[2L]], -50)
  expect_equal(result$yoy_pct_change[[3L]], -100)
  expect_true(is.na(result$yoy_pct_change[[5L]]))
  expect_equal(result$yoy_pct_change[[6L]], 100)
})

test_that("code transition audit filters the cohort before counting", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2020L, 2021L),
    I10_DX1 = c("I501", "I502", "I501", "J189"),
    DISCWT = c(2, 3, 7, 5),
    AGE = c(30L, 17L, NA_integer_, 40L)
  )
  result <- nis_audit_code_transition(data, list(hf = c("I50")),
    cohort = AGE >= 18, type = "dx")

  expect_equal(result$n_cohort_unweighted, c(1L, 1L))
  expect_equal(result$n_unweighted, c(1L, 0L))
  expect_equal(result$n_weighted, c(2, 0))
})

test_that("code transition audit agrees between data frames and lazy DuckDB", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L, 2020L),
    I10_PR1 = c("02UG0JZ", "02803ZZ", "02803ZZ", NA_character_),
    I10_DX1 = c("I509", "J189", "I50", "I501"),
    I10_PR2 = c("02UG0JZ", NA_character_, NA_character_, NA_character_),
    DISCWT = c(5, 4, 7, 2),
    AGE = c(40L, 50L, 60L, 16L)
  )
  path <- tempfile("nis-audit-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)
  codes <- list(myectomy = "02UG0JZ", ablation = "02803ZZ")

  from_frame <- nis_audit_code_transition(data, codes, cohort = AGE >= 18)
  from_duckdb <- nis_audit_code_transition(query, codes, cohort = AGE >= 18)
  from_frame_dx <- nis_audit_code_transition(data, list(hf = "I50"),
    cohort = AGE >= 18, type = "dx")
  from_duckdb_dx <- nis_audit_code_transition(query, list(hf = "I50"),
    cohort = AGE >= 18, type = "dx")

  expect_identical(from_duckdb, from_frame)
  expect_identical(from_duckdb_dx, from_frame_dx)
})

test_that("code transition audit validates named groups and columns", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)
  expect_error(nis_audit_code_transition(data, c("02UG0JZ")), "named")
  duplicate_codes <- c("02UG0JZ", "02UG0JZ")
  names(duplicate_codes) <- c("a", "a")
  expect_error(nis_audit_code_transition(data, duplicate_codes), "unique")
  expect_error(nis_audit_code_transition(data, list(a = NA_character_)), "non-missing")
  data$n_unweighted <- 1L
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"),
    by = "n_unweighted"), "summary column")
})

test_that("code transition audit validates periods, weights, and every code group", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)

  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), by = NA_character_), "`by`")
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), by = "MISSING"), "`by`")
  expect_error(nis_audit_code_transition(data, c(a = "02UG0JZ"), weight_var = "MISSING"),
    "`weight_var`")
  expect_error(nis_audit_code_transition(data, list(a = character())), "non-missing character")
  expect_error(nis_audit_code_transition(data, list(a = 1)), "non-missing character")
  expect_error(nis_audit_code_transition(data, list(a = c("02UG", NA_character_))),
    "non-missing character")
})

test_that("code transition audit avoids temporary names in user data", {
  data <- dplyr::tibble(
    .nis_audit_cohort = c(2020L, 2020L),
    .nis_audit_flag_1 = c("occupied", "occupied"),
    .nis_audit_n_1 = c(10L, 20L),
    .nis_audit_w_1 = c(1, 2),
    I10_PR1 = c("02UG0JZ", NA_character_),
    DISCWT = c(3, 4)
  )

  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"),
    by = ".nis_audit_cohort")

  expect_equal(result$n_cohort_unweighted, 2L)
  expect_equal(result$n_unweighted, 1L)
  expect_equal(result$n_weighted, 3)
})

test_that("code transition audit returns the empty grid for an empty cohort", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = "02UG0JZ", DISCWT = 1)
  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"),
    cohort = FALSE)

  expect_equal(nrow(result), 0L)
  expect_named(result, c("YEAR", "code_group", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "pct_within_year", "yoy_pct_change"))

  path <- tempfile("nis-audit-empty-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  from_duckdb <- nis_audit_code_transition(open_duckdb_dataset(path),
    c(myectomy = "02UG0JZ"), cohort = FALSE)
  expect_identical(from_duckdb, result)
})

test_that("code transition audit validates weights only in the selected cohort", {
  data <- dplyr::tibble(YEAR = 2020L, I10_PR1 = c("A", "B"),
    DISCWT = c(NA_real_, 2), KEEP = c(FALSE, TRUE))
  expect_error(nis_audit_code_transition(data, c(a = "A")), "finite, non-missing")
  expect_equal(nis_audit_code_transition(data, c(a = "A"), cohort = KEEP)$n_weighted, 0)
  expect_equal(nis_audit_code_transition(dplyr::mutate(data, DISCWT = c(0, -2)),
    c(a = "A"), cohort = !KEEP)$n_weighted, 0)
  for (bad in c(NA_real_, NaN, Inf, -Inf)) {
    expect_error(nis_audit_code_transition(dplyr::mutate(data, DISCWT = c(bad, 2)),
      c(a = "A")), "finite, non-missing")
  }
  for (bad in list(c("bad", "2"), c(TRUE, FALSE), factor(c("1", "2")))) {
    expect_error(nis_audit_code_transition(dplyr::mutate(data, DISCWT = bad),
      c(a = "A")), "numeric column")
  }
  expect_equal(nis_audit_code_transition(data, c(a = "A"), cohort = KEEP)$n_weighted, 0)
  expect_equal(nis_audit_code_transition(data, c(a = "B"), cohort = KEEP)$n_weighted, 2)
  expect_equal(nrow(nis_audit_code_transition(data, c(a = "A"), cohort = FALSE)), 0L)

  path <- tempfile("nis-audit-weights-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)
  expect_equal(nis_audit_code_transition(query, c(a = "A"), cohort = KEEP)$n_weighted, 0)
  expect_error(nis_audit_code_transition(query, c(a = "A")), "finite, non-missing")

  grouped <- dplyr::group_by(data, YEAR)
  expect_error(nis_audit_code_transition(grouped, c(a = "A")), "finite, non-missing")
  expect_equal(nis_audit_code_transition(grouped, c(a = "B"), cohort = KEEP)$n_weighted, 2)
  expect_equal(nis_audit_code_transition(grouped, c(a = "A"), cohort = FALSE),
    nis_audit_code_transition(data, c(a = "A"), cohort = FALSE))
  grouped_query <- dplyr::group_by(query, YEAR)
  expect_error(nis_audit_code_transition(grouped_query, c(a = "A")), "finite, non-missing")
  expect_equal(nis_audit_code_transition(grouped_query, c(a = "B"), cohort = KEEP)$n_weighted, 2)
})

test_that("missing periods have no year-over-year percentage change", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2020L, NA_integer_),
    I10_PR1 = c("02UG0JZ", NA_character_, "02UG0JZ"),
    DISCWT = c(1, 1, 1)
  )
  result <- nis_audit_code_transition(data, c(myectomy = "02UG0JZ"))

  expect_true(is.na(result$yoy_pct_change[[3L]]))
})

test_that("multi-column periods are sorted and compare consecutive periods", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L, 2020L, 2020L, 2020L),
    DQTR = c(2L, 1L, 1L, 1L, 2L, 2L),
    I10_PR1 = c("A1", "A1", "A1", "B1", "A1", "A1"),
    DISCWT = rep(2, 6)
  )
  result <- nis_audit_code_transition(data, c(a = "A"), by = c("YEAR", "DQTR"))

  expect_named(result, c("YEAR", "DQTR", "code_group", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "pct_within_year", "yoy_pct_change"))
  expect_equal(result$YEAR, c(2019L, 2019L, 2020L, 2020L))
  expect_equal(result$DQTR, c(1L, 2L, 1L, 2L))
  expect_equal(result$n_cohort_unweighted, c(1L, 1L, 2L, 2L))
  expect_equal(result$pct_within_year, c(100, 100, 50, 100))
  expect_equal(result$yoy_pct_change, c(NA, 0, -50, 100))
})

test_that("periods with a missing component stay explicit and never anchor a change", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L, 2020L),
    DQTR = c(1L, NA, 1L, NA),
    I10_PR1 = c("A1", "A1", NA, "A1"),
    DISCWT = rep(1, 4)
  )
  result <- nis_audit_code_transition(data, c(a = "A"), by = c("YEAR", "DQTR"))

  expect_equal(result$YEAR, c(2019L, 2020L, 2019L, 2020L))
  expect_equal(result$DQTR, c(1L, 1L, NA, NA))
  expect_equal(result$yoy_pct_change, c(NA, -100, NA, NA))
})

test_that("multi-column periods agree between data frames and lazy DuckDB", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L, 2020L, 2020L),
    DQTR = c(1L, NA, 1L, 2L, 2L),
    I10_PR1 = c("A1", "A2", "A1", NA, "B1"),
    DISCWT = c(1, 2, 3, 4, 5)
  )
  path <- tempfile("nis-audit-by-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data, file.path(path, "part-0.parquet"))
  query <- open_duckdb_dataset(path)

  for (output in c("summary", "inventory")) {
    expect_identical(
      nis_audit_code_transition(query, c(a = "A"), by = c("YEAR", "DQTR"), output = output),
      nis_audit_code_transition(data, c(a = "A"), by = c("YEAR", "DQTR"), output = output)
    )
  }
})

test_that("code transition audit validates multi-column periods", {
  data <- dplyr::tibble(YEAR = 2020L, DQTR = 1L, I10_PR1 = "A1", DISCWT = 1)
  codes <- c(a = "A")

  expect_error(nis_audit_code_transition(data, codes, by = character()), "`by`")
  expect_error(nis_audit_code_transition(data, codes, by = c("YEAR", "YEAR")), "`by`")
  expect_error(nis_audit_code_transition(data, codes, by = c("YEAR", "MISSING")), "`by`")
  expect_error(nis_audit_code_transition(data, codes, by = c("YEAR", NA_character_)), "`by`")
  expect_error(nis_audit_code_transition(data, codes, by = 2020L), "`by`")
  data$status <- 1L
  expect_error(nis_audit_code_transition(data, codes, by = c("YEAR", "status"),
    output = "inventory"), "summary column")
  expect_no_error(nis_audit_code_transition(data, codes, by = c("YEAR", "status")))
})

test_that("code inventory lists observed codes with absent and sparse periods", {
  data <- dplyr::tibble(
    YEAR = c(rep(2018L, 3), rep(2019L, 2), rep(2020L, 12)),
    I10_PR1 = c("02UG0JZ", "02UG0JZ", "02UG0ZZ", "02803ZZ", "02UG0JZ", rep("02UG0JZ", 12)),
    I10_PR2 = c(rep(NA_character_, 3), "02UG0JZ", rep(NA_character_, 13)),
    DISCWT = rep(2, 17)
  )
  result <- nis_audit_code_transition(data,
    c(myectomy = "02UG", ablation = "0280", missing = "ZZZ"),
    output = "inventory", sparse_n = 2L)

  expect_named(result, c("YEAR", "code_group", "code", "n_cohort_unweighted",
    "n_unweighted", "n_weighted", "status"))
  expect_equal(result$code_group, rep(c("myectomy", "myectomy", "ablation", "missing"),
    each = 3L))
  expect_equal(result$code[c(1L, 4L, 7L, 10L)],
    c("02UG0JZ", "02UG0ZZ", "02803ZZ", NA_character_))
  jz <- result[result$code %in% "02UG0JZ", ]
  expect_equal(jz$n_unweighted, c(2L, 2L, 12L))
  expect_equal(jz$n_weighted, c(4, 4, 24))
  expect_equal(jz$status, c("sparse", "sparse", "observed"))
  zz <- result[result$code %in% "02UG0ZZ", ]
  expect_equal(zz$status, c("sparse", "absent", "absent"))
  ablation <- result[result$code_group == "ablation", ]
  expect_equal(ablation$n_unweighted, c(0L, 1L, 0L))
  none <- result[result$code_group == "missing", ]
  expect_true(all(is.na(none$code)))
  expect_equal(none$n_unweighted, rep(0L, 3))
  expect_equal(none$status, rep("absent", 3))
  expect_equal(result$n_cohort_unweighted[1:3], c(3L, 2L, 12L))
})

test_that("code inventory counts a discharge once per code and honors the cohort", {
  data <- dplyr::tibble(
    YEAR = c(2020L, 2020L, 2020L),
    I10_DX1 = c("I501", "I509", "I501"),
    I10_DX2 = c("I501", "I501", "I509"),
    DISCWT = c(1, 2, 4),
    AGE = c(50L, 60L, 10L)
  )
  all_rows <- nis_audit_code_transition(data, c(hf = "I50"), type = "dx",
    output = "inventory")
  expect_equal(all_rows$code, c("I501", "I509"))
  expect_equal(all_rows$n_unweighted, c(3L, 2L))

  adults <- nis_audit_code_transition(data, c(hf = "I50"), type = "dx",
    cohort = AGE >= 18, output = "inventory")
  expect_equal(adults$n_cohort_unweighted, c(2L, 2L))
  expect_equal(adults$n_unweighted, c(2L, 1L))
  expect_equal(adults$n_weighted, c(3, 2))
})

test_that("code inventory tracks multi-column periods and missing components", {
  data <- dplyr::tibble(
    YEAR = c(2019L, 2019L, 2020L),
    DQTR = c(1L, NA, 1L),
    I10_PR1 = c("A1", "A1", "A2"),
    DISCWT = rep(1, 3)
  )
  result <- nis_audit_code_transition(data, c(a = "A"), by = c("YEAR", "DQTR"),
    output = "inventory")

  expect_equal(result$code, rep(c("A1", "A2"), each = 3L))
  expect_equal(result$YEAR, rep(c(2019L, 2020L, 2019L), 2L))
  expect_equal(result$DQTR, rep(c(1L, 1L, NA), 2L))
  expect_equal(result$status, c("sparse", "absent", "sparse", "absent", "sparse", "absent"))
})

test_that("code inventory respects the code system and validates arguments", {
  data <- dplyr::tibble(
    YEAR = c(2014L, 2016L),
    DX1 = c("4280", NA_character_),
    I10_DX1 = c(NA_character_, "I509"),
    DISCWT = c(1, 1)
  )
  icd9 <- nis_audit_code_transition(data, c(hf = "428"), type = "dx", system = "icd9",
    output = "inventory")
  expect_equal(icd9$code, c("4280", "4280"))
  expect_equal(icd9$n_unweighted, c(1L, 0L))
  icd10 <- nis_audit_code_transition(data, c(hf = "I50"), type = "dx", output = "inventory")
  expect_equal(icd10$code, c("I509", "I509"))
  expect_equal(icd10$n_unweighted, c(0L, 1L))

  expect_error(nis_audit_code_transition(data, c(hf = "I50"), type = "pr", output = "inventory"),
    "columns")
  expect_error(nis_audit_code_transition(data, c(hf = "I50"), type = "dx",
    output = "inventory", sparse_n = -1), "sparse_n")
  expect_error(nis_audit_code_transition(data, c(hf = "I50"), output = "bogus"), "should be one of")
  expect_error(nis_audit_code_transition(data, c(hf = "I.50"), type = "dx",
    output = "inventory"), NA)
  expect_equal(nrow(nis_audit_code_transition(data, c(hf = "I50"), type = "dx",
    cohort = FALSE, output = "inventory")), 0L)
})
