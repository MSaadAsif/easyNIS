test_that("code criteria agree across attrition, a survey model, and the transition audit", {
  nis <- nis_open(nis_example(years = 2015:2016)) |>
    dplyr::mutate(
      adult_age = dplyr::if_else(YEAR == 2015L & DQTR == 3L & HOSP_NIS == 1L, NA_real_, AGE),
      HOSP_NIS = dplyr::if_else(YEAR == 2015L & DQTR == 4L & HOSP_NIS == 2L, NA_integer_, HOSP_NIS),
      I10_DX1 = dplyr::if_else(YEAR == 2015L & DQTR == 3L, "I5022", I10_DX1),
      DX1 = dplyr::if_else(YEAR == 2015L & DQTR == 4L, "12345", DX1)
    )
  prefixes <- list(icd9 = c("123", "12345", "V0001"), icd10 = c("I50", "I5022", "Z515"))
  flow <- nis_attrition(
    nis,
    adults = adult_age >= 18,
    .codes = list(
      matching_dx = list(type = "dx", system = "both", position = "any", codes = prefixes),
      principal_dx = list(type = "dx", system = "both", position = "principal", codes = prefixes)
    ),
    .design = TRUE
  )

  # Each of 12 hospitals contributes 2 discharges per quarter. Invalid
  # hospital IDs remove 2 Q4 rows, and missing age removes 2 more in Q3.
  # Any ICD-9 slot matches all 24 discharges per quarter before exclusions.
  # The 2015 Q4 any-slot count is 19, of which 2 have invalid hospital IDs.
  # The 2016 any-slot quarter counts are 19, 12, 13 and 19.
  # Nine hospitals qualify on principal diagnosis in each year, each with
  # 2, 1, 1 and 2 discharges by quarter. Three of these are excluded in 2015.
  expect_identical(flow$n_unweighted, c(190L, 188L, 150L, 105L))
  criteria <- attr(flow, "nis_criteria")
  expect_identical(criteria$criterion, c("adults", "matching_dx", "principal_dx"))
  expect_identical(criteria$system, c(NA_character_, "both", "both"))
  expect_identical(criteria$position, c(NA_character_, "any", "principal"))
  expect_identical(criteria$codes, list(NULL, prefixes, prefixes))

  expect_warning(
    design <- nis_design(nis, cohort = !!nis_attrition_cohort(flow), keep = c(AGE, LOS)),
    "Excluded 2 discharges with invalid design fields"
  )
  fit <- survey::svyglm(LOS ~ AGE, design = design)
  expect_equal(stats::nobs(fit), tail(flow$n_unweighted, 1L))

  audit <- nis_audit_code_transition(nis, codes = flow, by = c("YEAR", "DQTR"))
  expect_identical(audit$n_cohort_unweighted, rep(24L, 16L))
  expect_identical(
    audit$n_unweighted,
    c(24L, 24L, 24L, 19L, 19L, 12L, 13L, 19L, 18L, 9L, 9L, 18L, 18L, 9L, 9L, 18L)
  )
})

test_that("single-system code criteria use their own slots and eras", {
  nis <- nis_open(nis_example(years = 2015))
  flow <- nis_attrition(
    nis,
    .codes = list(
      old_dx = list(type = "dx", system = "icd9", position = "principal", codes = "123"),
      new_pr = list(type = "pr", system = "icd10", position = "principal", codes = "0JH60")
    )
  )
  expect_identical(flow$n_unweighted, c(96L, 36L, 0L))
  audit <- nis_audit_code_transition(nis, flow, by = c("YEAR", "DQTR"))
  expect_identical(audit$n_unweighted, c(18L, 9L, 9L, 0L, 0L, 0L, 0L, 24L))
  expect_error(nis_audit_code_transition(nis, flow, output = "inventory"), "summary")
  expect_error(nis_audit_code_transition(nis, flow, system = "icd9"), "system")
  expect_error(
    nis_attrition(
      nis,
      old_dx = AGE >= 18,
      .codes = list(old_dx = list(type = "dx", system = "icd9", position = "principal", codes = "123"))
    ),
    "unique"
  )
})
