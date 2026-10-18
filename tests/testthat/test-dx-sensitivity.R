dx_sensitivity_fixture <- function() {
  dplyr::tibble(
    I10_DX1 = c("I421", "Z999", "I422", "Z999", NA_character_, "Z999"),
    I10_DX2 = c("I421", "I421", NA_character_, "I421", NA_character_, NA_character_),
    I10_DX3 = rep(NA_character_, 6L),
    DISCWT = c(2, 3, 5, 7, 11, 13),
    DIED = c(1, 0, NA, 1, 0, NA),
    ELECTIVE = c(1, 1, 0, NA, 1, 0)
  )
}

test_that("diagnosis position flags partition any-position cases", {
  data <- dx_sensitivity_fixture()
  flags <- nis_flag_dx_position(data, "I42", name = "hocm")

  expect_true(all(flags$hocm_principal <= flags$hocm_any))
  expect_false(any(flags$hocm_principal & flags$hocm_secondary_only))
  expect_identical(flags$hocm_principal | flags$hocm_secondary_only,
    flags$hocm_any)
  expect_identical(flags$hocm_principal, c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(flags$hocm_secondary_only, c(FALSE, TRUE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(flags$hocm_any, c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_error(nis_flag_dx_position(
    dplyr::mutate(data, hocm_any = FALSE), "I42", name = "hocm"
  ), "must not replace")
})

test_that("diagnosis sensitivity summary matches manual counts and rates", {
  data <- dx_sensitivity_fixture()
  out <- nis_dx_sensitivity(data, "I42")

  expect_identical(out$presentation, c("principal", "secondary_only", "any"))
  expect_equal(out$n_unweighted, c(2, 2, 4))
  expect_equal(out$n_weighted, c(7, 10, 17))
  expect_equal(out$pct_of_any_unweighted, c(50, 50, 100))
  expect_equal(out$pct_of_any_weighted, c(7 / 17 * 100, 10 / 17 * 100, 100))
  expect_equal(out$DIED_rate_unweighted, c(1, 1 / 2, 2 / 3))
  expect_equal(out$DIED_rate_weighted, c(2 / 2, 7 / 10, 9 / 12))
  expect_equal(out$ELECTIVE_rate_unweighted, c(1 / 2, 1, 2 / 3))
  expect_equal(out$ELECTIVE_rate_weighted, c(2 / 7, 3 / 3, 5 / 10))
  expect_error(nis_dx_sensitivity(data, "I42", outcomes = "MISSING"),
    "Missing requested outcome")
})

test_that("diagnosis sensitivity summary matches for a lazy Arrow query", {
  skip_if_not_installed("arrow")
  data <- dx_sensitivity_fixture()
  path <- tempfile("nis-dx-sensitivity-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  arrow::write_parquet(data, file.path(path, "part-0.parquet"))
  query <- arrow::open_dataset(path)

  lazy_flags <- nis_flag_dx_position(query, "I42", name = "hocm")
  expect_s3_class(lazy_flags, "arrow_dplyr_query")
  expect_identical(dplyr::collect(lazy_flags),
    nis_flag_dx_position(data, "I42", name = "hocm"))
  expect_equal(nis_dx_sensitivity(query, "I42"),
    nis_dx_sensitivity(data, "I42"))
})

test_that("sensitivity summary skips absent defaults and excludes missing outcomes", {
  data <- dx_sensitivity_fixture() |>
    dplyr::select(-DIED, -ELECTIVE)
  out <- nis_dx_sensitivity(data, "I42")
  expect_identical(names(out), c("presentation", "n_unweighted", "n_weighted",
    "pct_of_any_unweighted", "pct_of_any_weighted"))

  no_codes <- data |>
    dplyr::mutate(I10_DX1 = NA_character_, I10_DX2 = NA_character_)
  flags <- nis_flag_dx_position(no_codes, "I42")
  expect_false(any(flags$dx_principal | flags$dx_secondary_only | flags$dx_any))
})
