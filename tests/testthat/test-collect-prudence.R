collect_prudence_fixture <- function(.env = parent.frame()) {
  path <- withr::local_tempdir(.local_envir = .env)
  data <- data.frame(
    YEAR = 2020L,
    HOSP_NIS = rep(1:2, each = 500),
    NIS_STRATUM = 1L,
    DISCWT = 2,
    ID = 1:1000,
    TEXT = paste0(strrep("x", 2048), 1:1000)
  )
  write_duckdb_parquet(data, file.path(path, "NIS_2020.parquet"))
  write_duckdb_parquet(
    transform(data, YEAR = 2021L, ID = ID + 1000L),
    file.path(path, "NIS_2021.parquet")
  )
  query <- withr::with_options(
    list(easyNIS.duckdb_config = list(threads = 1L)),
    nis_open(path, check_release = FALSE)
  )
  con <- dbplyr::remote_con(query)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = .env)
  query
}

test_that("collect checks the projected result and respects explicit row limits", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(nis_collect_available = function() 4 * 1024^2)

  # The numeric projection is small; the long text crosses the danger line.
  expect_no_message(narrow <- dplyr::collect(dplyr::select(query, ID)))
  expect_equal(nrow(narrow), 2000L)
  expect_error(
    dplyr::collect(query),
    regexp = "(?s)filter.*select.*nis_design",
    class = "easyNIS_collect_too_large",
    perl = TRUE
  )
  expect_error(as.data.frame(query), class = "easyNIS_collect_too_large")
  expect_no_message(small <- as.data.frame(query, n = 3L))
  expect_equal(nrow(small), 3L)
  expect_no_message(empty <- dplyr::collect(utils::head(query, 0L)))
  expect_equal(nrow(empty), 0L)
  expect_no_message(filtered <- dplyr::collect(dplyr::filter(query, ID < 4L)))
  expect_equal(sort(filtered$ID), 1:3)

  withr::local_options(easyNIS.collect_prudence = FALSE)
  expect_no_message(full <- dplyr::collect(query))
  expect_equal(nrow(full), 2000L)
})

test_that("SQL row limits and collect caps use the available input estimate", {
  query <- dplyr::select(collect_prudence_fixture(), ID)
  memory <- 16 * 1024
  local_mocked_bindings(nis_collect_available = function() memory)

  ordered <- dplyr::arrange(query, ID)
  expect_error(dplyr::collect(utils::head(ordered, 1500L)), class = "easyNIS_collect_too_large")
  expect_error(dplyr::collect(utils::head(query, 1500L)), class = "easyNIS_collect_too_large")
  memory <- 256 * 1024
  expect_no_message(result <- dplyr::collect(query, n = 50000L))
  expect_equal(nrow(result), 2000L)
})

test_that("collect does not discover dynamic pivot columns during preflight", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(nis_collect_available = function() 1024^3)
  con <- dbplyr::remote_con(query)
  collect_pivot <- function(guard, sequence) {
    withr::local_options(easyNIS.collect_prudence = guard)
    DBI::dbExecute(con, paste("CREATE SEQUENCE", sequence, "START 1"))
    pivot <- dbplyr::sql(sprintf(
      "(SELECT \"0\" FROM (PIVOT (SELECT nextval('%s') %% 3 AS k FROM range(2000)) ON k USING count(*)) AS piv)",
      sequence
    ))
    result <- query |>
      dplyr::select(ID) |>
      dplyr::mutate(n = !!pivot) |>
      dplyr::collect()
    expect_equal(nrow(result), 2000L)
    as.numeric(DBI::dbGetQuery(con, sprintf("SELECT currval('%s') AS n", sequence))$n)
  }
  without_guard <- collect_pivot(FALSE, "pivot_off")
  expect_equal(collect_pivot(TRUE, "pivot_on"), without_guard)
})

test_that("the message band permits a collect and tiny results stay quiet", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(nis_collect_available = function() 32 * 1024^2)

  expect_message(full <- dplyr::collect(query), "Collecting.*MiB")
  expect_equal(nrow(full), 2000L)
  expect_no_message(summary <- dplyr::collect(dplyr::summarise(query, n = dplyr::n())))
  expect_equal(as.numeric(summary$n), 2000)
})

test_that("a selective filter is counted before an estimated abort", {
  query <- collect_prudence_fixture() |>
    dplyr::filter(ID %% 999L == 0L) |>
    dplyr::select(ID)
  local_mocked_bindings(nis_collect_available = function() 1024)

  expect_no_message(cohort <- dplyr::collect(query))
  expect_equal(sort(cohort$ID), c(999L, 1998L))
})

test_that("preflight does not run an expensive lazy filter before collecting", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(nis_collect_available = function() 1024^3)
  con <- dbplyr::remote_con(query)
  DBI::dbExecute(con, "CREATE SEQUENCE collect_calls START 1")
  filtered <- query |>
    dplyr::filter(dbplyr::sql("nextval('collect_calls') <= 2000")) |>
    dplyr::select(ID)

  expect_no_message(result <- dplyr::collect(filtered))
  expect_equal(nrow(result), 2000L)
  expect_equal(as.numeric(DBI::dbGetQuery(con, "SELECT currval('collect_calls') AS n")$n), 2000)
})

test_that("easyNIS helpers check their DuckDB collections", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(nis_collect_available = function() 2 * 1024^2)
  text_fields <- stats::setNames(rep(list(rlang::sym("TEXT")), 64L), paste0("TEXT", 1:64))
  wide <- dplyr::mutate(query, !!!text_fields)

  expect_error(
    nis_design(wide, cohort = TRUE, keep = dplyr::starts_with("TEXT"), annualize = FALSE),
    class = "easyNIS_collect_too_large"
  )
  expect_message(
    design <- nis_design(query, cohort = ID %% 1000L < 4L, keep = ID, annualize = FALSE),
    "^Cohort:"
  )
  expect_s3_class(design, "tbl_svy")
})

test_that("unavailable memory permits collection with one session message", {
  query <- collect_prudence_fixture()
  local_mocked_bindings(ps_system_memory = function() stop("memory unavailable"), .package = "ps")
  withr::local_options(rlib_message_verbosity = "default")

  expect_message(dplyr::collect(query, n = 1L), "available system memory")
  expect_no_message(dplyr::collect(query, n = 1L))
})
