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
    expect_match(conditionMessage(condition), normalizePath(annual, winslash = "/"), fixed = TRUE)
    expect_match(conditionMessage(condition), normalizePath(hive, winslash = "/"), fixed = TRUE)
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
    write_duckdb_parquet(data.frame(id = 2L), file.path(path, "YEAR=2020", "part.parquet"))
    write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L), file.path(path, "NIS_2019.parquet"))
    write_duckdb_parquet(data.frame(id = 3L), file.path(path, "YEAR=2021", "part.parquet"))

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
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 1L), file.path(annual, "part-1.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 2L), file.path(annual, "nested", "part-2.parquet"))

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
  write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 2L), file.path(path, "NIS_2020.parquet", "part.parquet"))
  write_duckdb_parquet(data.frame(id = 3L), file.path(path, "YEAR=2021", "part.parquet"))

  result <- dplyr::collect(nis_open(path))
  result <- result[order(result$id), ]
  expect_identical(result$YEAR, 2019:2021)
  expect_identical(result$id, 1:3)
  selected <- dplyr::collect(nis_open(path, years = c(2020L, 2021L)))
  selected <- selected[order(selected$id), ]
  expect_identical(selected$YEAR, 2020:2021)
  expect_identical(selected$id, 2:3)
})


test_that("nested Hive parts belong to their nearest selected year", {
  path <- tempfile("nis-nested-hive-")
  dir.create(path)
  withr::defer(unlink(path, recursive = TRUE))
  write_duckdb_parquet(data.frame(id = 1L), file.path(path, "YEAR=2020", "outer.parquet"))
  write_duckdb_parquet(data.frame(id = 2L), file.path(path, "YEAR=2020", "YEAR=2021", "inner.parquet"))

  outer <- dplyr::collect(nis_open(path, 2020L))
  expect_identical(outer$YEAR, 2020L)
  expect_identical(outer$id, 1L)
  inner <- dplyr::collect(nis_open(path, 2021L))
  expect_identical(inner$YEAR, 2021L)
  expect_identical(inner$id, 2L)
  both <- nis_open(path) |> dplyr::arrange(YEAR) |> dplyr::collect()
  expect_identical(both$id, 1:2)
})

test_that("the selected query reports exactly its Parquet parts", {
  path <- tempfile("nis-part-manifest-")
  dir.create(path)
  withr::defer(unlink(path, recursive = TRUE))
  annual <- file.path(path, "NIS_2019.parquet")
  outer <- file.path(path, "YEAR=2020", "outer.parquet")
  inner <- file.path(path, "YEAR=2020", ".nested", "YEAR=2021", "inner.parquet")
  unrelated <- file.path(path, "not-an-entry", "unrelated.parquet")
  write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L), annual)
  write_duckdb_parquet(data.frame(id = 2L), outer)
  write_duckdb_parquet(data.frame(id = 3L), inner)
  write_duckdb_parquet(data.frame(id = 4L), unrelated)

  query <- nis_open(path, years = c(2019L, 2021L)) |>
    dplyr::select(YEAR, id)
  expect_identical(nis_open_source_paths(query), normalizePath(c(annual, inner), winslash = "/"))
  expect_identical(nis_open_available_years(path), 2019:2021)
  expect_identical(sort(dplyr::collect(nis_open(path))$id), 1:3)
})

test_that("an explicitly selected empty year is reported with other years present", {
  path <- tempfile("nis-empty-year-")
  dir.create(file.path(path, "NIS_2020.parquet"), recursive = TRUE)
  withr::defer(unlink(path, recursive = TRUE))
  write_duckdb_parquet(data.frame(YEAR = 2019L, id = 1L), file.path(path, "NIS_2019.parquet"))

  expect_error(nis_open(path, years = 2019:2020), "no Parquet part files.*2020")
  expect_identical(dplyr::collect(nis_open(path))$YEAR, 2019L)
  expect_identical(nis_open_available_years(path), 2019L)
})


test_that("partition years come from inside the supplied directory", {
  path <- file.path(tempfile("nis-partition-parent-"), "YEAR=2020", "incoming")
  dir.create(path, recursive = TRUE)
  withr::defer(unlink(dirname(dirname(path)), recursive = TRUE))
  write_duckdb_parquet(data.frame(YEAR = 2021L, id = 1L), file.path(path, "NIS_2021.parquet"))
  expect_identical(dplyr::collect(nis_open(path, 2021L))$YEAR, 2021L)

  hive <- file.path(path, "YEAR=2022")
  write_duckdb_parquet(data.frame(id = 2L), file.path(hive, "part.parquet"))
  expect_identical(dplyr::collect(nis_open(hive))$YEAR, 2022L)
})

test_that("native Parquet parts are read at their literal paths", {
  path <- tempfile("nis-literal-parquet-path-")
  dir.create(path)
  withr::defer(unlink(path, recursive = TRUE))
  hive <- file.path(path, "YEAR=2020")
  write_duckdb_parquet(data.frame(id = 1L), file.path(hive, "part[1].parquet"))
  write_duckdb_parquet(data.frame(id = 2L), file.path(hive, "part1.parquet"))
  expect_no_warning(query <- nis_open(path))
  expect_identical(sort(dplyr::collect(query)$id), 1:2)
})

test_that("a physical year conflict identifies the offending part of a Hive scan", {
  path <- tempfile("nis-grouped-hive-year-")
  withr::defer(unlink(path, recursive = TRUE))
  hive <- file.path(path, "YEAR=2020")
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 1L), file.path(hive, "part1.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2021L, id = 2L), file.path(hive, "part[2].parquet"))

  expect_error(nis_open(path), "physical .*YEAR.* conflict.*part\\[2\\][.]parquet")
})

test_that("invalid annual years identify every offending part of a scan", {
  path <- tempfile("nis-grouped-annual-year-")
  withr::defer(unlink(path, recursive = TRUE))
  annual <- file.path(path, "NIS_2020.parquet")
  write_duckdb_parquet(data.frame(YEAR = 2020, id = 1L), file.path(annual, "part1.parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2020.5, id = 2L), file.path(annual, "part[2].parquet"))
  write_duckdb_parquet(data.frame(YEAR = 2147483648, id = 3L), file.path(annual, "part3.parquet"))

  error <- tryCatch(nis_open(path), error = identity)
  expect_s3_class(error, "rlang_error")
  message <- conditionMessage(error)
  expect_match(message, "Invalid .*YEAR")
  expect_match(message, "part[2].parquet", fixed = TRUE)
  expect_match(message, "part3.parquet", fixed = TRUE)
  expect_false(grepl("part1.parquet", message, fixed = TRUE))
})


for (type in c("BIGINT", "UBIGINT")) {
  test_that(paste("native annual", type, "years keep the integer bounds"), {
    path <- tempfile("nis-integer-year-")
    annual <- file.path(path, "NIS_2020.parquet")
    dir.create(annual, recursive = TRUE)
    withr::defer(unlink(path, recursive = TRUE))
    con <- DBI::dbConnect(duckdb::duckdb())
    withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
    write_years <- function(years, name) {
      values <- paste0("(", years, "::", type, ")", collapse = ", ")
      destination <- DBI::dbQuoteString(con, file.path(annual, name))
      statement <- paste0(
        "COPY (SELECT * FROM (VALUES ",
        values,
        ") AS t(\"YEAR\")) TO ",
        destination,
        " (FORMAT PARQUET)"
      )
      DBI::dbExecute(con, statement)
    }

    lower <- if (type == "BIGINT") "(-2147483648)" else "0"
    write_years(c(lower, "2147483647", "NULL"), "part-valid.parquet")
    actual <- nis_open(path, check_release = FALSE) |>
      dplyr::summarise(rows = dplyr::n()) |>
      dplyr::collect()
    expect_equal(actual$rows, 3)

    extreme <- if (type == "BIGINT") "(-2147483649)" else "18446744073709551615"
    write_years(extreme, "part[bad].parquet")
    write_years("2147483648", "part-high.parquet")
    error <- tryCatch(nis_open(path), error = identity)
    expect_s3_class(error, "rlang_error")
    expect_match(conditionMessage(error), "part[bad].parquet", fixed = TRUE)
    expect_match(conditionMessage(error), "part-high.parquet", fixed = TRUE)
    expect_false(grepl("part-valid.parquet", conditionMessage(error), fixed = TRUE))
  })
}

test_that("a Hive dataset root owns repeated year partitions and literal names", {
  path <- file.path(tempfile("nis-root-hive-"), "YEAR=2020")
  withr::defer(unlink(dirname(path), recursive = TRUE))
  outer <- file.path(path, "part[1].parquet")
  inner <- file.path(path, "YEAR=2020", "part[2].parquet")
  write_duckdb_parquet(data.frame(id = 1L), outer)
  write_duckdb_parquet(data.frame(id = 2L), inner)

  query <- nis_open(path, 2020L)
  expect_setequal(nis_open_source_paths(query), normalizePath(c(outer, inner), winslash = "/"))
  result <- query |> dplyr::arrange(id) |> dplyr::collect()
  expect_identical(result$id, 1:2)
  expect_identical(result$YEAR, c(2020L, 2020L))
})

test_that("non-scalar physical Hive years cannot pass partition validation", {
  path <- tempfile("nis-list-year-")
  hive <- file.path(path, "YEAR=2020")
  dir.create(hive, recursive = TRUE)
  withr::defer(unlink(path, recursive = TRUE))
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  destination <- DBI::dbQuoteString(con, file.path(hive, "part.parquet"))
  DBI::dbExecute(con, paste0("COPY (SELECT [2020]::INTEGER[] AS YEAR, 1 AS id) TO ", destination, " (FORMAT PARQUET)"))
  expect_error(nis_open(path), "physical .*YEAR.* conflict")
})
