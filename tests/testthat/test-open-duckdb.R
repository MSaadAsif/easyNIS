corrupt_parquet_marker <- function(file, marker) {
  bytes <- readBin(file, "raw", n = file.info(file)$size)
  needle <- charToRaw(marker)
  starts <- which(vapply(
    seq_len(length(bytes) - length(needle) + 1L),
    function(i) identical(bytes[i:(i + length(needle) - 1L)], needle),
    logical(1)
  ))
  testthat::expect_gt(length(starts), 0L)
  bytes[starts[[1L]]] <- as.raw(0xFF)
  writeBin(bytes, file)
}

test_that("nis_open reads native Parquet lazily and normalizes case drift", {
  path <- tempfile("nis-duckdb-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), Hosp_Nis = c(101L, 102L), AGE = c(40L, 70L)),
    file.path(path, "NIS_2019.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2020L, 2020L), Hosp_Nis = c(201L, 202L), AGE = c(65L, 30L)),
    file.path(path, "NIS_2020.parquet")
  )

  duckdb_query <- nis_open(path, years = 2020L, check_release = FALSE)
  expect_s3_class(duckdb_query, "tbl_duckdb_connection")
  expect_true(all(c("YEAR", "HOSP_NIS") %in% colnames(duckdb_query)))
  expect_false("Hosp_Nis" %in% colnames(duckdb_query))

  duckdb_result <- duckdb_query |>
    dplyr::filter(AGE >= 50) |>
    dplyr::summarise(n = dplyr::n(), hospitals = dplyr::n_distinct(HOSP_NIS)) |>
    dplyr::collect()
  expect_equal(duckdb_result$n, 1)
  expect_error(nis_open(path, years = 2020L, engine = "duckdb"), "unused argument")
})

test_that("easyNIS explains invalid UTF-8 during collection", {
  path <- tempfile("nis-invalid-utf8-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)

  marker <- "SYNTHMARK"
  data <- data.frame(YEAR = 2020L, DISCWT = 5, AGE = 60L, FEMALE = "Female", DIED = "No", I10_DX1 = marker)
  file <- file.path(path, "NIS_2020.parquet")
  write_duckdb_parquet(data, file)
  corrupt_parquet_marker(file, marker)

  expect_error(
    nis_audit_code_transition(nis_open(path, check_release = FALSE), c(marker = marker), type = "dx"),
    "A string column in the Parquet input is not valid UTF-8"
  )
})
test_that("invalid UTF-8 in a release field warns and keeps clean columns queryable", {
  path <- withr::local_tempdir()
  file <- file.path(path, "NIS_2020.parquet")
  write_duckdb_parquet(data.frame(YEAR = 2020L, id = 7L, NIS_STRATUM = "SYNTHMARK"), file)
  corrupt_parquet_marker(file, "SYNTHMARK")

  expect_warning(query <- nis_open(path), "UTF-8", class = "easynis_release_check_failed")
  expect_identical(dplyr::collect(dplyr::select(query, id))$id, 7L)
  expect_error(nis_collect(dplyr::select(query, NIS_STRATUM)), "UTF-8")
})

test_that("Arrow reader preserves invalid UTF-8 bytes and integer years", {
  skip_if_not_installed("arrow")
  local_mocked_bindings(
    nis_release_reference = data.frame(
      year = 2020L,
      rows = 1,
      weight = 5,
      hospitals = 1
    )
  )
  path <- tempfile("nis-arrow-invalid-utf8-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  marker <- "SYNTHMARK"
  file <- file.path(path, "NIS_2020.parquet")
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, id = 7L, NIS_STRATUM = marker), file)
  corrupt_parquet_marker(file, marker)

  expect_no_warning(query <- nis_open(path, years = 2020L, reader = "arrow"))
  result <- dplyr::collect(
    query |>
      dplyr::select(YEAR, id, NIS_STRATUM)
  )
  expect_type(result$YEAR, "integer")
  expect_identical(result$YEAR, 2020L)
  expect_identical(result$id, 7L)
  expect_identical(
    charToRaw(result$NIS_STRATUM[[1L]]),
    c(
      as.raw(0xFF),
      as.raw(0x59),
      as.raw(0x4E),
      as.raw(0x54),
      as.raw(0x48),
      as.raw(0x4D),
      as.raw(0x41),
      as.raw(0x52),
      as.raw(0x4B)
    )
  )
})

test_that("Arrow reader unions mixed annual and Hive schemas", {
  skip_if_not_installed("arrow")
  path <- tempfile("nis-arrow-hive-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L, annual = "a"), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(NA_integer_, 2020L), id = 2:3, hive = c("b", "c")),
    file.path(path, "YEAR=2020", "part.parquet")
  )
  result <- dplyr::collect(
    nis_open(path, reader = "arrow", check_release = FALSE) |>
      dplyr::select(YEAR, id, annual, hive)
  )
  expect_type(result$YEAR, "integer")
  expect_setequal(result$YEAR, c(2019L, 2020L, 2020L))
  expect_setequal(result$id, 1:3)
  expect_identical(result$annual[!is.na(result$annual)], "a")
  expect_setequal(result$hive[!is.na(result$hive)], c("b", "c"))
})

test_that("Arrow reader rejects physical years that conflict with Hive partitions", {
  skip_if_not_installed("arrow")
  path <- tempfile("nis-arrow-year-conflict-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L), file.path(path, "YEAR=2020", "part.parquet"))
  expect_error(nis_open(path, reader = "arrow"), "physical `YEAR`.*Hive")
})

test_that("nis_open safely quotes paths containing spaces and apostrophes", {
  path <- file.path(tempdir(), "nis quoted 'path'")
  dir.create(path, showWarnings = FALSE)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  parquet <- file.path(path, "NIS_2019.parquet")
  write_duckdb_parquet(dplyr::tibble(YEAR = rep(2019L, 3)), parquet)
  query <- nis_open(path, check_release = FALSE)
  result <- query |>
    dplyr::summarise(n = dplyr::n()) |>
    dplyr::collect()
  expect_equal(result$n, 3)
})

test_that("nis_open reads Hive year partitions and unions their schemas", {
  path <- tempfile("nis-hive-years-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), A = c(1L, 2L), drift = c(10L, 20L)),
    file.path(path, "YEAR=2019", "part.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = 2020L, B = 3L, drift = 30.5),
    file.path(path, "YEAR=2020", "part.parquet")
  )

  query <- nis_open(path, check_release = FALSE)
  expect_s3_class(query, "tbl_sql")
  all_years <- dplyr::collect(query |> dplyr::select(YEAR, A, B, drift))
  expect_equal(all_years$YEAR, c(2019L, 2019L, 2020L))
  expect_equal(all_years$A, c(1L, 2L, NA_integer_))
  expect_equal(all_years$B, c(NA_integer_, NA_integer_, 3L))
  expect_equal(all_years$drift, c(10, 20, 30.5))
  selected_year <- dplyr::collect(
    nis_open(path, years = 2020L, check_release = FALSE) |>
      dplyr::select(YEAR, B, drift)
  )
  expect_equal(selected_year$YEAR, 2020L)
  expect_equal(selected_year$drift, 30.5)
})

test_that("nis_open pushes selected columns down to Parquet", {
  path <- tempfile("nis-hive-projection-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, 2019L), A = c(1L, 2L), drift = c(10L, 20L)),
    file.path(path, "YEAR=2019", "part.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = 2020L, B = 3L, drift = 30.5),
    file.path(path, "YEAR=2020", "part.parquet")
  )

  query <- nis_open(path, check_release = FALSE)
  sql <- dbplyr::sql_render(query |> dplyr::select(YEAR, B))
  skip_if_not_installed("jsonlite")
  plan <- DBI::dbGetQuery(
    query$src$con,
    paste(
      "EXPLAIN (FORMAT JSON)",
      as.character(sql)
    )
  )
  plan_json <- jsonlite::fromJSON(plan[[2L]], simplifyVector = FALSE)
  parquet_projections <- function(node) {
    if (!is.list(node)) {
      return(character())
    }
    projections <- character()
    if (is.character(node$name) && grepl("PARQUET", node$name, ignore.case = TRUE)) {
      projections <- unlist(node$extra_info$Projections, use.names = FALSE)
    }
    children <- node$children
    if (is.null(children)) {
      return(projections)
    }
    c(projections, unlist(lapply(children, parquet_projections), use.names = FALSE))
  }
  projection_tokens <- unlist(lapply(plan_json, parquet_projections), use.names = FALSE)
  expect_gt(length(projection_tokens), 0L)
  expect_setequal(projection_tokens[nzchar(projection_tokens)], "B")
})

test_that("nis_open combines annual files with Hive partitions", {
  path <- tempfile("nis-mixed-layouts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L, annual_only = "a"), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 2L, hive_only = "b"), file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(nis_open(path, check_release = FALSE) |> dplyr::select(YEAR, id, annual_only, hive_only))
  expect_identical(sort(result$YEAR), c(2019L, 2020L))
  expect_identical(sort(result$id), c(1L, 2L))
  expect_identical(result$annual_only[!is.na(result$annual_only)], "a")
  expect_identical(result$hive_only[!is.na(result$hive_only)], "b")
  selected <- dplyr::collect(
    nis_open(path, years = 2020L, check_release = FALSE) |>
      dplyr::select(YEAR, id)
  )
  expect_identical(selected$YEAR, 2020L)
  expect_identical(selected$id, 2L)
})

test_that("nis_open rejects a year represented in both layouts", {
  path <- tempfile("nis-duplicate-layouts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  annual <- file.path(path, "NIS_2020.parquet")
  hive <- file.path(path, "YEAR=2020")
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, id = 1L), annual)
  write_duckdb_parquet(dplyr::tibble(id = 2L), file.path(hive, "part.parquet"))

  expect_error(nis_open(path), "2020.*NIS_2020[.]parquet.*YEAR=2020.*Keep one layout")
})

test_that("nis_open checks mixed layouts only for selected years", {
  path <- tempfile("nis-selected-layout-conflict-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, id = 2L), file.path(path, "NIS_2020.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 3L), file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(
    nis_open(path, years = 2019L, check_release = FALSE) |>
      dplyr::select(YEAR, id)
  )
  expect_identical(result$YEAR, 2019L)
  expect_identical(result$id, 1L)
  expect_error(nis_open(path, years = 2020L), "Year 2020: annual .*NIS_2020[.]parquet.*Hive .*YEAR=2020")
})

test_that("nis_open accepts Hive parts within one annual dataset", {
  path <- tempfile("nis-nested-annual-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(id = 1L), file.path(path, "NIS_2020.parquet", "YEAR=2020", "part.parquet"))
  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  for (reader in readers) {
    for (years in list(NULL, 2020L)) {
      result <- dplyr::collect(nis_open(path, years = years, reader = reader, check_release = FALSE))
      expect_identical(result$id, 1L)
      expect_identical(result$YEAR, 2020L)
    }
    write_duckdb_parquet(dplyr::tibble(id = 2L), file.path(path, "YEAR=2020", "part.parquet"))
    expect_error(nis_open(path, reader = reader), "both annual and Hive")
    unlink(file.path(path, "YEAR=2020"), recursive = TRUE)
  }
})

test_that("nis_open accepts annual parts within one Hive dataset", {
  path <- tempfile("nis-nested-hive-")
  hive <- file.path(path, "YEAR=2020")
  dir.create(hive, recursive = TRUE)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(id = 1L), file.path(hive, "NIS_2020.parquet", "part.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 2L), file.path(hive, "extra.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 3L), file.path(hive, "batch-b", "YEAR=2020", "part.parquet"))
  readers <- c("duckdb", if (requireNamespace("arrow", quietly = TRUE)) "arrow")
  for (reader in readers) {
    for (spelling in c(hive, paste0(hive, "/"), file.path(hive, "."))) {
      for (years in list(NULL, 2020L)) {
        result <- dplyr::collect(nis_open(spelling, years = years, reader = reader, check_release = FALSE))
        expect_identical(sort(result$id), 1:3)
        expect_identical(result$YEAR, rep(2020L, 3L))
      }
    }
  }
})

test_that("nis_open accepts multiple Hive parts for one year", {
  path <- tempfile("nis-hive-multiple-parts-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(id = 1:2), file.path(path, "YEAR=2020", "part-1.parquet"))
  write_duckdb_parquet(dplyr::tibble(id = 3L), file.path(path, "YEAR=2020", "part-2.parquet"))

  result <- dplyr::collect(nis_open(path, check_release = FALSE) |> dplyr::select(YEAR, id))
  expect_identical(result$YEAR, rep(2020L, 3L))
  expect_identical(result$id, 1:3)
})

test_that("nis_open casts physical Hive years before combining annual files", {
  path <- tempfile("nis-mixed-year-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, id = 1L), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = "2020", id = 2L), file.path(path, "YEAR=2020", "part.parquet"))

  result <- dplyr::collect(nis_open(path, check_release = FALSE) |> dplyr::select(YEAR, id))
  expect_type(result$YEAR, "integer")
  expect_identical(result$YEAR, c(2019L, 2020L))
  expect_identical(result$id, c(1L, 2L))
})

test_that("nis_open casts YEAR to integer and rejects non-numeric years", {
  path <- tempfile("nis-year-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(
      YEAR = 2019L,
      I10_DX1 = "I509",
      I10_PR1 = "02703ZZ"
    ),
    file.path(path, "NIS_2019.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(
      YEAR = "2020",
      I10_DX1 = "J189",
      I10_PR1 = "0JH60DZ"
    ),
    file.path(path, "NIS_2020.parquet")
  )

  query <- nis_open(path, check_release = FALSE)
  result <- query |>
    nis_flag_dx(hf = "I50") |>
    nis_flag_pr(proc = "02703") |>
    dplyr::collect()
  expect_type(result$YEAR, "integer")
  expect_identical(result$hf, c(TRUE, FALSE))
  expect_identical(result$proc, c(TRUE, FALSE))

  write_duckdb_parquet(dplyr::tibble(YEAR = "unknown"), file.path(path, "NIS_2021.parquet"))
  expect_error(nis_open(path, years = 2021L), "YEAR.*NIS_2021[.]parquet")

  for (bad_year in c("2019.5", "2147483648")) {
    write_duckdb_parquet(dplyr::tibble(YEAR = bad_year), file.path(path, "NIS_2022.parquet"))
    expect_error(nis_open(path, years = 2022L), "whole numbers within the integer range")
    unlink(file.path(path, "NIS_2022.parquet"))
  }
})

test_that("nis_open rejects physical years that conflict with Hive partitions", {
  path <- tempfile("nis-hive-year-conflict-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, NA_integer_), id = 1:2),
    file.path(path, "YEAR=2019", "part-a.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(YEAR = 2020L, id = 3L),
    file.path(path, "YEAR=2019", "part-b.parquet")
  )
  write_duckdb_parquet(
    dplyr::tibble(id = 4L),
    file.path(path, "YEAR=2020", "part.parquet")
  )

  expect_error(nis_open(path, years = 2019L), "physical.*YEAR=2019")
  valid_path <- tempfile("nis-hive-year-valid-")
  dir.create(valid_path)
  on.exit(unlink(valid_path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(YEAR = c(2019L, NaN), id = 1:2),
    file.path(valid_path, "YEAR=2019", "part-a.parquet")
  )
  write_duckdb_parquet(dplyr::tibble(id = 3L), file.path(valid_path, "YEAR=2019", "part-b.parquet"))

  query <- nis_open(valid_path, check_release = FALSE)
  expect_s3_class(query, "tbl_duckdb_connection")
  expect_equal(dplyr::collect(query |> dplyr::select(YEAR, id))$YEAR, c(2019L, 2019L, 2019L))
})

test_that("nis_open unions representative all-NA Parquet column types", {
  path <- tempfile("nis-nullable-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(
    dplyr::tibble(
      YEAR = c(2019L, 2019L),
      nullable_integer = c(NA_integer_, NA_integer_),
      nullable_double = c(NA_real_, NA_real_),
      nullable_character = c(NA_character_, NA_character_),
      nullable_date = as.Date(c(NA_character_, NA_character_))
    ),
    file.path(path, "NIS_2019.parquet")
  )

  result <- dplyr::collect(nis_open(path, check_release = FALSE))
  expect_type(result$nullable_integer, "integer")
  expect_type(result$nullable_double, "double")
  expect_type(result$nullable_character, "character")
  expect_s3_class(result$nullable_date, "Date")
  expect_true(all(is.na(result$nullable_integer)))
  expect_true(all(is.na(result$nullable_double)))
  expect_true(all(is.na(result$nullable_character)))
  expect_true(all(is.na(result$nullable_date)))
})

test_that("nis_open promotes numeric and character fields to character", {
  path <- tempfile("nis-incompatible-types-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(dplyr::tibble(YEAR = 2019L, field = 1L), file.path(path, "NIS_2019.parquet"))
  write_duckdb_parquet(dplyr::tibble(YEAR = 2020L, field = "two"), file.path(path, "NIS_2020.parquet"))

  query <- nis_open(path, check_release = FALSE)
  expect_s3_class(query, "tbl_sql")
  result <- dplyr::collect(query |> dplyr::select(YEAR, field))
  expect_type(result$field, "character")
  expect_equal(result$field, c("1", "two"))
})

test_that("derived DuckDB queries retain the connection until all are released", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")

  path <- tempfile("nis-duckdb-finalizer-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  write_duckdb_parquet(data.frame(YEAR = 2019L), file.path(path, "NIS_2019.parquet"))

  query <- nis_open(path, check_release = FALSE)
  con <- query$src$con
  lookup <- dplyr::tibble(YEAR = 2019L, adjustment = 2L)
  DBI::dbWriteTable(con, "lookup", lookup, temporary = TRUE)
  derived <- query |>
    dplyr::mutate(value = YEAR + 1L) |>
    dplyr::left_join(dplyr::tbl(con, "lookup"), by = "YEAR")
  expect_true(duckdb::dbIsValid(con))
  query <- NULL
  invisible(gc())
  expect_true(duckdb::dbIsValid(con))
  expect_equal(dplyr::collect(derived)$value, 2020L)
  derived <- NULL
  lookup <- NULL
  invisible(gc())
  expect_false(duckdb::dbIsValid(con))
})


test_that("open queries apply workload limits and own separate spill locations", {
  spill <- tempfile("nis-spill-parent-")
  dir.create(spill)
  withr::defer(unlink(spill, recursive = TRUE))
  withr::local_options(
    easyNIS.duckdb_config = list(
      memory_limit = "96MB",
      threads = 2L,
      temp_directory = spill,
      max_temp_directory_size = "1GB",
      preserve_insertion_order = FALSE
    )
  )
  path <- nis_example(2020L)
  withr::defer(unlink(path, recursive = TRUE))
  queries <- list(nis_open(path), nis_open(path))
  settings <- lapply(queries, function(query) {
    con <- dbplyr::remote_con(query)
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT current_setting('threads') AS threads, current_setting('memory_limit') AS memory,",
        "current_setting('temp_directory') AS spill, current_setting('preserve_insertion_order') AS ordered"
      )
    )
  })
  expect_equal(vapply(settings, function(setting) as.numeric(setting$threads), 0), c(2, 2))
  expect_identical(vapply(settings, function(setting) setting$ordered, FALSE), c(FALSE, FALSE))
  expect_true(all(vapply(settings, function(setting) nzchar(setting$memory), FALSE)))
  spill_paths <- vapply(settings, function(setting) setting$spill, "")
  expect_length(unique(spill_paths), 2L)
  expect_identical(dirname(spill_paths), rep(normalizePath(spill, winslash = "/"), 2L))
  expect_true(all(dir.exists(spill_paths)))
  if (.Platform$OS.type == "unix") {
    expect_identical(as.character(file.mode(spill_paths)), rep("700", 2L))
  }
  missing_path <- tempfile("nis-empty-source-")
  dir.create(missing_path)
  withr::defer(unlink(missing_path, recursive = TRUE))
  bad <- data.frame(YEAR = 2020.5)
  write_duckdb_parquet(bad, file.path(missing_path, "NIS_2020.parquet"))
  expect_error(nis_open(missing_path), "Invalid .*YEAR")
  expect_setequal(list.dirs(spill, recursive = FALSE, full.names = FALSE), basename(spill_paths))
})

test_that("an export that exceeds the configured spill cap fails and releases spill space", {
  spill <- withr::local_tempdir()
  path <- nis_example(2020L)
  withr::defer(unlink(path, recursive = TRUE))
  withr::local_options(
    easyNIS.duckdb_config = list(
      memory_limit = "32MB",
      max_temp_directory_size = "1MB",
      threads = 1L,
      preserve_insertion_order = FALSE,
      temp_directory = spill
    )
  )
  query <- nis_open(path)
  con <- dbplyr::remote_con(query)
  file <- file.path(spill, "sorted.parquet")
  output <- DBI::dbQuoteString(con, file)
  sql <- paste0(
    "COPY (SELECT i, md5(i::VARCHAR) AS tag FROM range(1000000) AS t(i) ",
    "ORDER BY tag, i) TO ",
    output,
    " (FORMAT PARQUET)"
  )
  expect_error(DBI::dbExecute(con, sql), "max_temp_directory_size")
  unlink(file)
  rm(query)
  invisible(gc())
  expect_false(DBI::dbIsValid(con))
  expect_true(dir.exists(spill))
  expect_length(list.files(spill, all.files = TRUE, no.. = TRUE), 0L)
})
