test_that("mixed-system flags match explicit era-specific flags", {
  nis <- nis_open(nis_example(years = 2015))
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(nis), shutdown = TRUE))
  for (data in list(nis, dplyr::collect(nis))) {
    mixed <- data |>
      nis_flag_dx(dx = list(icd9 = "12345", icd10 = "I50"), system = "both") |>
      nis_flag_pr(pr = list(icd9 = "0123", icd10 = "02L"), system = "both")
    explicit <- data |>
      nis_flag_dx(flag_dx9 = "12345", system = "icd9") |>
      nis_flag_dx(flag_dx10 = "I50") |>
      nis_flag_pr(flag_pr9 = "0123", system = "icd9") |>
      nis_flag_pr(flag_pr10 = "02L") |>
      dplyr::mutate(dx = flag_dx9 | flag_dx10, pr = flag_pr9 | flag_pr10)
    tally <- function(data) {
      data |>
        dplyr::count(DQTR, dx, pr) |>
        dplyr::arrange(DQTR, dx, pr) |>
        dplyr::collect()
    }
    observed <- tally(mixed)
    expect_equal(observed, tally(explicit))
    expect_true(all(c(FALSE, TRUE) %in% observed$dx))
  }
})

test_that("mixed diagnoses honor position and require both code definitions and slot sets", {
  toy <- data.frame(
    YEAR = c(2014L, 2015L, 2015L, 2016L),
    DQTR = c(1L, 3L, 4L, 1L),
    DXVER = c(9L, 10L, 10L, 10L),
    DX1 = c("123", "123", "123", "123"),
    I10_DX1 = c("Z500", "Z500", "I509", "Z500"),
    I10_DX2 = rep("I509", 4L)
  )
  definitions <- list(icd9 = "123", icd10 = list(prefix = "I50"))
  expect_identical(
    nis_flag_dx(toy, flag = definitions, system = "both", position = "principal")$flag,
    c(TRUE, FALSE, TRUE, FALSE)
  )
  expect_error(nis_flag_dx(toy, flag = "I50", system = "both"), "icd9.*icd10")
  expect_error(
    nis_flag_dx(dplyr::select(toy, -DX1), flag = definitions, system = "both"),
    "No ICD-9 DX columns"
  )
})
