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
  con <- dbplyr::remote_con(source)
  settings <- function() {
    DBI::dbGetQuery(con, "SELECT current_setting('partitioned_write_flush_threshold') AS flush")
  }
  initial_settings <- settings()
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
  expect_identical(settings(), initial_settings)
  expect_identical(list.files(parent, all.files = TRUE, no.. = TRUE), contents)
  expect_equal(nrow(dplyr::collect(source)), 96L)

  nis_write_cohort(source, AGE >= 65, path, LOS)
  expect_identical(settings(), initial_settings)
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

test_that("an enriched example can be saved and reopened as a survey domain", {
  skip_if_not_installed("medicalcoder", "0.10.0")
  local_sql_na_warnings()
  sample <- nis_open(nis_example(2019:2020))
  reference <- nis_design(sample, cohort = I10_DX1 == "I5022", keep = LOS)
  expect_warning(
    source <- sample |>
      dplyr::select(YEAR, KEY_NIS, HOSP_NIS, NIS_STRATUM, DISCWT, AGE, LOS, I10_DX1, I10_DX2) |>
      nis_comorbidity(method = "charlson_quan2005") |>
      nis_add_ccsr(position = "default"),
    "No matching POA column"
  )
  expect_s3_class(source, "tbl_lazy")
  expect_match(as.character(dbplyr::sql_render(source)), "read_parquet", fixed = TRUE)

  path <- nis_write_cohort(.data = source, cohort = ccsr == "CIR019", path = tempfile(), keep = c(LOS, cmrb_any))
  design <- nis_design(nis_open(path), keep = c(LOS, cmrb_any))
  expect_equal(nrow(design$variables), 108L)
  expect_type(design$variables$cmrb_any, "logical")
  expect_equal(nis_cell_counts(design, by = starts_with("cmrb"))$n |> sum(), 108L)
  actual <- survey::svymean(~LOS, design)
  expected <- survey::svymean(~LOS, reference)
  expect_equal(coef(actual), coef(expected))
  expect_equal(vcov(actual), vcov(expected))
})

test_that("saved cohort field names survive reopen and resave verbatim", {
  root <- withr::local_tempdir()
  raw <- file.path(root, "source")
  dir.create(raw)
  write_duckdb_parquet(
    data.frame(
      YEAR = 2019L,
      HOSP_NIS = 1:2,
      NIS_STRATUM = 1L,
      DISCWT = 5,
      Source_Field = c(1L, 9L)
    ),
    file.path(raw, "NIS_2019.parquet")
  )
  source <- nis_open(raw, check_release = FALSE)
  expect_true("SOURCE_FIELD" %in% colnames(source))
  source <- dplyr::mutate(source, display_Label = SOURCE_FIELD > 2L)
  saved <- nis_write_cohort(source, SOURCE_FIELD > 2L, file.path(root, "saved"), display_Label)
  reopened <- nis_open(saved)
  selected <- dplyr::collect(dplyr::select(reopened, tidyselect::all_of("display_Label"), .in_cohort))
  expect_identical(selected$display_Label[selected$.in_cohort], TRUE)
  expect_identical(selected$display_Label[!selected$.in_cohort], NA)
  resaved <- nis_write_cohort(reopened, path = file.path(root, "resaved"), keep = display_Label)
  expect_identical(colnames(nis_open(resaved)), colnames(reopened))
})

test_that("a cohort export rejects conflicting strata even for cohort hospitals", {
  root <- withr::local_tempdir()
  write_duckdb_parquet(
    data.frame(YEAR = 2019L, HOSP_NIS = 1L, NIS_STRATUM = 1:2, DISCWT = 5, LOS = 2L),
    file.path(root, "NIS_2019.parquet")
  )
  source <- nis_open(root, check_release = FALSE)
  path <- file.path(root, "cohort")
  expect_error(nis_write_cohort(source, TRUE, path, LOS), "Each hospital must map to one stratum")
  expect_false(dir.exists(path))
})
