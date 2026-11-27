test_that("nis_cell_counts rejects reserved summary names in cell keys", {
  records <- data.frame(
    YEAR = rep(2020, 4),
    HOSP_NIS = c(1, 2, 1, 2),
    NIS_STRATUM = 1,
    DISCWT = 1,
    group = c("A", "A", "B", "B"),
    n = c("first", "first", "second", "second"),
    hospitals = c("north", "south", "north", "south")
  )
  inputs <- list(
    records,
    srvyr::as_survey_design(records, ids = HOSP_NIS, weights = DISCWT),
    nis_design(records, TRUE, keep = c(group, n, hospitals))
  )
  keys <- list("n", "hospitals", c("group", "n"), c("hospitals", "group"), c("n", "hospitals", "group"))

  for (input in inputs) {
    for (by in keys) {
      expect_error(nis_cell_counts(input, by = dplyr::all_of(by)), "`by`.*reserved.*(n|hospitals)")
    }
  }
})

test_that("Parquet cell counts retain year scope and reject invalid identities", {
  records <- data.frame(
    YEAR = c(2020L, 2020L, 2021L, 2020L),
    HOSP_NIS = c(1, 1, 1, Inf),
    N = c("one", "one", "one", NA_character_)
  )
  path <- tempfile("nis-cells-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(records, file.path(path, "NIS_2020.parquet"))
  query <- nis_open(path, check_release = FALSE)
  valid <- dplyr::filter(query, is.finite(HOSP_NIS))
  expect_error(nis_cell_counts(query, N), "finite positive")
  expect_equal(nis_cell_counts(valid, N), nis_cell_counts(records[1:3, ], N))
  expect_equal(nis_cell_counts(valid)$hospitals, 2)
  expect_equal(nis_cell_counts(dplyr::filter(query, FALSE))$n, 0)
  expect_error(nis_cell_counts(dplyr::mutate(query, HOSP_NIS = "1"), N), "finite positive")
})

test_that("nis_cell_counts retains ordinary multi-key identities and counts", {
  records <- data.frame(
    YEAR = c(2020, 2020, 2021, 2020, 2020, 2020),
    HOSP_NIS = c(1, 1, 1, 2, 3, 4),
    NIS_STRATUM = 1,
    DISCWT = 1,
    group = c("A", "A", "A", "A", "B", "B"),
    category = c("north", "north", "north", "south", "north", "south"),
    eligible = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    n = "source label",
    hospitals = "source hospital label"
  )
  inputs <- list(
    records[records$eligible, ],
    srvyr::as_survey_design(records[records$eligible, ], ids = HOSP_NIS, weights = DISCWT),
    nis_design(records, eligible, keep = c(group, category, n, hospitals))
  )

  for (input in inputs) {
    counts <- nis_cell_counts(input, by = c(group, category))
    expect_identical(names(counts), c("group", "category", "n", "hospitals"))
    expect_identical(counts$group, c("A", "A", "B"))
    expect_identical(counts$category, c("north", "south", "north"))
    expect_identical(counts$n, c(3L, 1L, 1L))
    expect_identical(counts$hospitals, c(2L, 1L, 1L))
  }
})
