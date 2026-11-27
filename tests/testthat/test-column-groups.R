test_that("column groups compose without capturing derived fields", {
  incomplete <- data.frame(
    AGE = 50L,
    RACE = 2L,
    DIED = 0L,
    DX1 = "4280",
    I10_DX40 = "I509",
    DXPOA40 = "Y",
    ECODE1 = "E849",
    DXVER = 9L,
    NDX = 3L,
    PR1 = "0010",
    I10_PR25 = "02L",
    PRDAY25 = 1L,
    PRVER = 9L,
    NPR = 1L,
    HOSP_NIS = 1L,
    HOSP_DIVISION = 4L,
    YEAR = 2015L,
    S_DISC_U = 99L,
    DQTR = 2L,
    DX1_flag = TRUE,
    I10_DX01 = "I509",
    PRDAY_total = 5L
  )

  expect_named(dplyr::select(incomplete, nis_vars_demographics()), c("AGE", "RACE"))
  expect_named(
    dplyr::select(incomplete, nis_vars_dx()),
    c("DX1", "I10_DX40", "DXPOA40", "ECODE1", "DXVER", "NDX")
  )
  expect_named(
    dplyr::select(incomplete, nis_vars_pr()),
    c("PR1", "I10_PR25", "PRDAY25", "PRVER", "NPR")
  )
  expect_named(
    dplyr::select(incomplete, nis_vars_hospital()),
    c("HOSP_NIS", "HOSP_DIVISION")
  )
  expect_named(
    dplyr::select(incomplete, nis_vars_design()),
    c("YEAR", "HOSP_NIS", "DQTR")
  )
  expect_named(
    dplyr::select(incomplete, c(nis_vars_dx(), where(is.logical)), -nis_vars_dx()),
    "DX1_flag"
  )
  expect_named(
    dplyr::select(incomplete["DIED"], nis_vars_demographics()),
    character()
  )
})

test_that("a lazy projection preserves cohort flags and required survey fields", {
  path <- nis_example(years = 2015)
  nis <- nis_open(path)
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(nis), shutdown = TRUE))

  projected <- nis |>
    dplyr::select(c(nis_vars_design(), nis_vars_dx(), nis_vars_demographics()), LOS)
  expect_s3_class(projected, "tbl_lazy")
  expect_false("TOTCHG" %in% colnames(projected))

  flags <- function(data) {
    data |>
      nis_flag_dx(hf9 = "12345", system = "icd9") |>
      nis_flag_dx(hf10 = "I50")
  }
  summarize <- function(data) {
    flags(data) |>
      nis_design(cohort = AGE >= 18 & (hf9 | hf10), keep = LOS) |>
      srvyr::summarise(total = srvyr::survey_total(), mean_los = srvyr::survey_mean(LOS))
  }
  expect_equal(summarize(projected), summarize(nis))

  design_input <- dplyr::select(nis, nis_vars_design(), LOS)
  for (field in c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")) {
    missing_field <- dplyr::select(design_input, -dplyr::all_of(field))
    expect_error(nis_design(missing_field), paste0("missing design column.*", field))
  }
})
