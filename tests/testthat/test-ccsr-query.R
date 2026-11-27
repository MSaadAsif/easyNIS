ccsr_test_reference <- function() {
  path <- withr::local_tempdir(.local_envir = parent.frame())
  releases <- data.frame(
    type = c("dx", "dx", "pr"),
    version = c("2020.3", "2021.2", "2021.1")
  )
  diagnosis <- data.frame(
    type = "dx",
    version = c(rep("2020.3", 2), rep("2021.2", 3)),
    code = c("A000", "A000", "A000", "A000", "A001"),
    category = c("ZZZ001", "ZZZ002", "ZZZ001", "ZZZ002", "ZZZ003"),
    inpatient = c("Y", "N", "N", "Y", "X"),
    outpatient = c("N", "Y", "Y", "N", "Y")
  )
  procedure <- data.frame(
    type = "pr",
    version = "2021.1",
    code = "0016070",
    category = "ZZP001",
    inpatient = NA_character_,
    outpatient = NA_character_
  )
  map <- rbind(diagnosis, procedure)
  categories <- unique(map[c("type", "version", "category")])
  categories$description <- paste("Invented category", categories$category)
  queries <- nis_open(nis_example(years = 2019:2020))
  con <- dbplyr::remote_con(queries)
  withr::defer(DBI::dbDisconnect(con), envir = parent.frame())
  utils::write.csv(releases, file.path(path, "releases.csv"), row.names = FALSE)
  nis_duckdb_write_parquet(map, file.path(path, "map.parquet"), con)
  nis_duckdb_write_parquet(categories, file.path(path, "categories.parquet"), con)
  list(con = con, query = queries, path = path)
}

test_that("one-slot CCSR lets DuckDB skip unused input expressions", {
  ref <- ccsr_test_reference()
  local_mocked_bindings(ccsr_reference_dir = function() ref$path)
  query <- dplyr::mutate(
    ref$query,
    unused = dbplyr::sql("CASE WHEN KEY_NIS > 0 THEN error('Unused enrichment evaluated')::BOOLEAN END")
  )
  enriched <- nis_add_ccsr(query, position = "default")
  totals <- enriched |>
    dplyr::count(ccsr) |>
    dplyr::collect()
  expect_equal(sum(totals$n), 192)
  expect_error(dplyr::collect(dplyr::select(enriched, unused)), "Unused enrichment evaluated")
})

test_that("CCSR assigns exact codes in DuckDB using the release for each NIS year", {
  ref <- ccsr_test_reference()
  local_mocked_bindings(ccsr_reference_dir = function() ref$path)
  inputs <- data.frame(
    id = 1:8,
    YEAR = c(2014L, 2015L, 2015L, 2019L, 2020L, 2020L, 2020L, 2021L),
    DQTR = c(4L, 3L, 4L, 4L, 4L, 1L, 4L, 1L),
    DXVER = c(9L, 9L, 10L, NA, NA, NA, NA, NA),
    I10_DX2 = c(rep("A000", 4), NA, NA, "A000", "A000"),
    I10_DX1 = c("A000", "A000", "A000", "A001", "A001", "A0000", "A000", "A000"),
    I10_PR1 = "0016070"
  )
  data <- dplyr::copy_to(ref$con, inputs, "ccsr_inputs")
  local_mocked_bindings(nis_collect = function(...) stop("Unexpected early collection"))
  result <- data |>
    nis_add_ccsr() |>
    nis_add_ccsr(position = "principal", name = "principal") |>
    nis_add_ccsr(position = "default", name = "default") |>
    nis_add_ccsr(version = "2021.2", position = "default", name = "pinned") |>
    nis_add_ccsr(version = "2020.3", position = "default", name = "older") |>
    nis_add_ccsr(type = "pr", name = "procedure")
  expect_s3_class(result, "tbl_sql")
  expect_match(as.character(dbplyr::sql_render(result)), "read_parquet")

  out <- dplyr::collect(dplyr::arrange(result, id))
  expect_identical(out$id, inputs$id)
  expect_true(all(is.na(out$default[c(1:2, 4:6, 8)])))
  expect_identical(out$default[c(3, 7)], c("ZZZ001", "ZZZ002"))
  expect_identical(out$pinned[3], "ZZZ002")
  expect_identical(out$pinned[8], "ZZZ002")
  expect_true(is.na(out$older[7]))
  expect_setequal(out$ccsr[[3]], c("ZZZ001", "ZZZ002"))
  expect_setequal(out$ccsr[[4]], c("ZZZ001", "ZZZ002"))
  expect_length(out$principal[[4]], 0L)
  expect_identical(out$principal[[5]], "ZZZ003")
  expect_length(out$ccsr[[6]], 0L)
  expect_setequal(out$ccsr[[7]], c("ZZZ001", "ZZZ002"))
  expect_identical(out$procedure[[5]], "ZZP001")
  expect_error(nis_add_ccsr(data, version = "1999.1"), "1999.1")
})

test_that("a CCSR-enriched query can be saved after its original query goes out of scope", {
  path <- nis_example(years = 2020)
  withr::defer(unlink(path, recursive = TRUE))
  output <- file.path(withr::local_tempdir(), "cohort")

  classified <- nis_open(path) |>
    nis_add_ccsr(position = "default")
  invisible(gc())

  nis_write_cohort(classified, AGE >= 18, output, keep = c(AGE, ccsr))
  restored <- nis_open(output) |>
    nis_design(keep = c(AGE, ccsr))

  expect_gt(nrow(restored$variables), 0)
  expect_true(all(restored$variables$AGE >= 18))
  expect_true("ccsr" %in% names(restored$variables))
})

test_that("CCSR works through nis_open on invented annual Parquet files", {
  ref <- ccsr_test_reference()
  local_mocked_bindings(ccsr_reference_dir = function() ref$path)
  classifications <- ref$query |>
    dplyr::mutate(I10_DX1 = "A000") |>
    nis_add_ccsr(categories = "ZZZ002", position = "principal") |>
    nis_add_ccsr(position = "default", name = "main_ccsr") |>
    dplyr::distinct(YEAR, ccsr, main_ccsr) |>
    dplyr::arrange(YEAR)
  out <- dplyr::collect(classifications)
  expect_equal(out$YEAR, 2019:2020)
  expect_identical(out$main_ccsr, c("ZZZ001", "ZZZ002"))
  expect_identical(out$ccsr, list("ZZZ002", "ZZZ002"))
  expect_identical(nis_ccsr_codes(categories = "ZZZ003", version = "2021.2"), "A001")
  expect_identical(nis_ccsr_codes(categories = "ZZZ002", version = "2020.3", default_only = TRUE), character())
})
