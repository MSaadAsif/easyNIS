for (annual_type in c("file", "directory")) {
  test_that(paste("nis_open rejects annual", annual_type, "and Hive duplicates"), {
    path <- tempfile("nis-layout-conflict-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    annual <- file.path(path, "NIS_2020.parquet")
    annual_part <- if (annual_type == "directory") {
      file.path(annual, "part.parquet")
    } else {
      annual
    }
    hive <- file.path(path, "YEAR=2020")
    write_duckdb_parquet(data.frame(YEAR = 2020L, id = 1L), annual_part)
    write_duckdb_parquet(data.frame(id = 1L), file.path(hive, "part.parquet"))

    condition <- tryCatch(nis_open(path), error = identity)
    expect_s3_class(condition, "rlang_error")
    expect_match(conditionMessage(condition), "both annual and Hive layouts")
    expect_match(conditionMessage(condition), "Year 2020", fixed = TRUE)
    expect_match(conditionMessage(condition), annual, fixed = TRUE)
    expect_match(conditionMessage(condition), hive, fixed = TRUE)
    expect_identical(as.character(conditionCall(condition)[[1L]]), "nis_open")
    expect_error(nis_open(path, years = 2020L), "both annual and Hive layouts")
  })

  test_that(paste("nis_open checks only selected years for annual", annual_type), {
    path <- tempfile("nis-selected-layouts-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    annual <- file.path(path, "NIS_2020.parquet")
    annual_part <- if (annual_type == "directory") {
      file.path(annual, "part.parquet")
    } else {
      annual
    }
    write_duckdb_parquet(data.frame(YEAR = 2020L, id = 2L), annual_part)
    write_duckdb_parquet(data.frame(id = 2L),
      file.path(path, "YEAR=2020", "part.parquet"))
    write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L),
      file.path(path, "NIS_2019.parquet"))
    write_duckdb_parquet(data.frame(id = 3L),
      file.path(path, "YEAR=2021", "part.parquet"))

    expect_error(nis_open(path, years = c(2019L, 2020L)), "both annual and Hive layouts")
    annual_result <- dplyr::collect(nis_open(path, years = 2019L))
    expect_identical(annual_result$YEAR, 2019L)
    expect_identical(annual_result$id, 1L)
    hive_result <- dplyr::collect(nis_open(path, years = 2021L))
    expect_identical(hive_result$YEAR, 2021L)
    expect_identical(hive_result$id, 3L)
    selected <- dplyr::collect(nis_open(path, years = c(2019L, 2021L)))
    selected <- selected[order(selected$id), ]
    expect_identical(selected$YEAR, c(2019L, 2021L))
    expect_identical(selected$id, c(1L, 3L))
  })
}

test_that("nis_open reads all parts of a valid annual directory", {
  path <- tempfile("nis-annual-directory-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  annual <- file.path(path, "NIS_2020.parquet")
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 1L),
    file.path(annual, "part-1.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 2L),
    file.path(annual, "nested", "part-2.parquet"))

  for (years in list(NULL, 2020L)) {
    result <- dplyr::collect(nis_open(path, years = years))
    expect_identical(result$YEAR, c(2020L, 2020L))
    expect_setequal(result$id, 1:2)
    expect_equal(nrow(result), 2L)
  }
})

test_that("nis_open combines annual files, directories and Hive in different years", {
  path <- tempfile("nis-mixed-layouts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L),
    file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 2L),
    file.path(path, "NIS_2020.parquet", "part.parquet"))
  write_duckdb_parquet(data.frame(id = 3L),
    file.path(path, "YEAR=2021", "part.parquet"))

  result <- dplyr::collect(nis_open(path))
  result <- result[order(result$id), ]
  expect_identical(result$YEAR, 2019:2021)
  expect_identical(result$id, 1:3)
  selected <- dplyr::collect(nis_open(path, years = c(2020L, 2021L)))
  selected <- selected[order(selected$id), ]
  expect_identical(selected$YEAR, 2020:2021)
  expect_identical(selected$id, 2:3)
})
