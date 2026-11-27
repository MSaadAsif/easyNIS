test_that("the design labels documented residence and ICD-10 indicator values", {
  nis <- nis_open(nis_example(years = 2023))
  on.exit(DBI::dbDisconnect(dbplyr::remote_con(nis), shutdown = TRUE))

  prepared <- nis |>
    dplyr::mutate(
      PL_NCHS2 = ifelse(HOSP_NIS %% 2L == 0L, 21L, 22L),
      I10_BIRTH = HOSP_NIS %% 4L,
      I10_SERVICELINE = 1L + HOSP_NIS %% 5L
    )
  design <- nis_design(prepared, cohort = TRUE, keep = c(PL_NCHS2, I10_BIRTH, I10_SERVICELINE))
  expect_identical(levels(design$variables$PL_NCHS2), c("Metropolitan", "Nonmetropolitan"))
  expect_identical(
    levels(design$variables$I10_BIRTH),
    c("No birth diagnosis", "Born in hospital", "Born outside hospital", "Place of birth unspecified")
  )
  expect_identical(
    levels(design$variables$I10_SERVICELINE),
    c("Maternal and neonatal", "Mental health or substance use", "Injury", "Surgical", "Medical")
  )
  expect_identical(
    as.character(design$variables$PL_NCHS2),
    ifelse(design$variables$HOSP_NIS %% 2L == 0L, "Metropolitan", "Nonmetropolitan")
  )
})

test_that("labels preserve annual residence fields and keep unknown codes visible", {
  input <- data.frame(PL_NCHS2006 = c(1L, 6L, NA), PL_NCHS2 = c(21L, 98L, NA))
  expect_warning(labelled <- nis_label(input), "Unknown code.*PL_NCHS2")
  expect_identical(
    as.character(labelled$PL_NCHS2006),
    c("Central metro, population 1 million or more", "Nonmetropolitan, nonmicropolitan", NA)
  )
  expect_identical(as.character(labelled$PL_NCHS2), c("Metropolitan", "Code 98", NA))
  expect_identical(nis_label(labelled), labelled)
})
