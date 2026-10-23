test_that("lazy probe column discovery keeps diagnosis and POA fields", {
  data <- dplyr::tibble(
    YEAR = 2022L,
    HOSP_NIS = 1L,
    NIS_STRATUM = 1L,
    DISCWT = 1,
    AGE = 54L,
    eligible = TRUE,
    I10_DX1 = "I210",
    I10_DX2 = "E119",
    DXPOA1 = "Y",
    DXPOA2 = "N"
  )
  query <- duckdb_query_fixture(data)

  diagnosis_fields <- easyNIS:::probe_diagnosis_columns(query)
  expected_fields <- c("I10_DX1", "I10_DX2", "DXPOA1", "DXPOA2")
  expect_setequal(diagnosis_fields, expected_fields)

  design <- query |>
    nis_flag_dx(ami = "I21") |>
    nis_design(ami, keep = c(AGE, tidyselect::all_of(diagnosis_fields)))

  collected <- dplyr::collect(design$variables)
  expect_true(all(expected_fields %in% names(collected)))
  expect_equal(collected$I10_DX1, "I210")
  expect_equal(collected$DXPOA1, "Y")
})
