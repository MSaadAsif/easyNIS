test_that("saved cohorts preserve the full variance design and count only patients", {
  source <- nis_open(nis_example(2019:2020)) |>
    nis_flag_dx(heart_failure = "I50", position = "principal")
  keep <- c("AGE", "LOS")
  path <- tempfile("saved-cohort-")
  expect_identical(
    nis_write_cohort(source, YEAR == 2019L & NIS_STRATUM <= 2L & heart_failure, path, keep),
    path
  )
  saved <- expect_no_warning(nis_open(path), class = "easynis_release_mismatch")
  rows <- dplyr::collect(saved)
  expect_setequal(names(rows), c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT", keep, ".in_cohort"))
  expect_equal(sum(!rows$.in_cohort & rows$YEAR == 2020L), 12)
  expect_equal(sum(!rows$.in_cohort & rows$YEAR == 2019L), 6)
  expect_true(all(is.na(rows$LOS[!rows$.in_cohort])))
  expect_error(nis_write_cohort(source, FALSE, path, keep), "already exists")
  expect_error(nis_design(saved, TRUE, keep), "Omit .*cohort")
  expect_error(
    nis_design(dplyr::select(saved, -.in_cohort), keep = keep),
    "Keep .*in_cohort.*membership column"
  )

  estimates <- function(design) {
    dplyr::summarise(
      design,
      n = srvyr::unweighted(dplyr::n()),
      total = srvyr::survey_total(),
      mean_los = srvyr::survey_mean(LOS)
    )
  }
  domain <- function(design) dplyr::filter(design, AGE >= 40L, HOSP_NIS %% 4L != 1L)
  for (annualize in c(FALSE, TRUE)) {
    expect_warning(
      fresh <- nis_design(source, YEAR == 2019L & NIS_STRATUM <= 2L & heart_failure, keep, annualize),
      "No cohort discharges"
    )
    expect_warning(reopened <- nis_design(saved, keep = keep, annualize = annualize), "No cohort discharges")
    expect_true(all(abs(estimates(fresh) - estimates(reopened)) <= 1e-12))
    expect_true(all(abs(estimates(domain(fresh)) - estimates(domain(reopened))) <= 1e-12))
    expect_equal(nrow(reopened$variables), sum(rows$.in_cohort))
  }

  copied <- nis_write_cohort(saved, path = tempfile("copied-cohort-"), keep = LOS)
  copy_design <- suppressWarnings(nis_design(nis_open(copied), keep = LOS, annualize = TRUE))
  expect_true(all(abs(estimates(copy_design) - estimates(reopened)) <= 1e-12))

  if (requireNamespace("gtsummary", quietly = TRUE)) {
    table <- gtsummary::tbl_svysummary(
      domain(reopened),
      include = LOS,
      type = LOS ~ "continuous",
      statistic = LOS ~ "{N_obs_unweighted}"
    )
    expect_identical(table$table_body$stat_0, as.character(nrow(domain(reopened)$variables)))
  }
})

test_that("an export failure leaves no target and the source remains usable", {
  parent <- nis_example(2019L)
  source <- nis_open(parent)
  contents <- list.files(parent, all.files = TRUE, no.. = TRUE)
  path <- file.path(parent, "cohort")
  expect_error(
    nis_write_cohort(
      source,
      dbplyr::sql("CASE WHEN AGE >= 0 THEN error('export interrupted') ELSE FALSE END"),
      path,
      LOS
    ),
    "export interrupted"
  )
  expect_identical(list.files(parent, all.files = TRUE, no.. = TRUE), contents)
  expect_equal(nrow(dplyr::collect(source)), 96L)

  nis_write_cohort(source, AGE >= 65, path, LOS)
  expect_equal(nrow(dplyr::collect(nis_open(parent))), 96L)
  expect_lt(nrow(dplyr::collect(nis_open(path))), 96L)
})

test_that("cohort exports cannot publish when all design weights are invalid", {
  withr::local_options(easyNIS.duckdb_config = list(threads = 1L))
  root <- withr::local_tempdir()
  write_duckdb_parquet(
    data.frame(YEAR = 2019L, HOSP_NIS = 1L, NIS_STRATUM = 1L, DISCWT = c(0, NA_real_), LOS = c(1L, 3L)),
    file.path(root, "NIS_2019.parquet")
  )
  source <- nis_open(root, check_release = FALSE)
  con <- dbplyr::remote_con(source)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(
    nis_write_cohort(source, TRUE, file.path(root, "cohort"), LOS),
    "No discharges have valid design fields"
  )
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "NIS_2019.parquet")
})

test_that("the release exemption comes from the Parquet footer", {
  source <- nis_open(nis_example(2019L))
  path <- nis_write_cohort(source, AGE >= 65, tempfile(), LOS)
  expect_no_warning(saved <- nis_open(path), class = "easynis_release_mismatch")
  con <- dbplyr::remote_con(saved)
  parts <- list.files(path, recursive = TRUE, full.names = TRUE)
  metadata <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT key::VARCHAR AS key, value::VARCHAR AS value FROM parquet_kv_metadata(",
      DBI::dbQuoteString(con, parts),
      ")"
    )
  )
  entries <- stats::setNames(metadata$value, metadata$key)
  expect_match(entries[["easyNIS_cohort"]], "AGE >= 65", fixed = TRUE)
  expect_identical(entries[["easyNIS_source_years"]], "2019")
  expect_identical(entries[["easyNIS_version"]], as.character(utils::packageVersion("easyNIS")))
  expect_identical(entries[["easyNIS_source"]], "non_release")

  unmarked <- tempfile()
  dir.create(unmarked)
  file <- DBI::dbQuoteString(con, file.path(unmarked, "NIS_2019.parquet"))
  sql <- dbplyr::sql_render(saved)
  DBI::dbExecute(con, paste0("COPY (", sql, ") TO ", file, " (FORMAT PARQUET)"))
  expect_warning(nis_open(unmarked), class = "easynis_release_mismatch")
})
