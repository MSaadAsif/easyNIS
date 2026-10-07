test_that("invented fixtures preserve component keys and identifier precision", {
  for (year in 2017:2022) {
    fixture <- nis_synthetic_data(year)
    core <- fixture$core
    expect_equal(nrow(core), 12L)
    expect_true(all(core$YEAR == year))
    expect_type(core$KEY_NIS, "character")
    expect_identical(core$KEY_NIS[1], "9007199254741001")
    expect_identical(fixture$hospital$HOSP_NIS, sprintf("%04d", 1:4))
    expect_false(anyDuplicated(core$KEY_NIS) > 0L)
    expect_identical(core$KEY_NIS, fixture$severity$KEY_NIS)
    joined <- merge(core, fixture$hospital, by = c("YEAR", "HOSP_NIS", "NIS_STRATUM"))
    expect_equal(nrow(joined), 12L)
    expect_true("001" %in% core$I10_DX2)
    expect_equal(sum(is.na(core$DIED)), 4L)
    expect_equal(sum(is.na(core$AGE)), 1L)
    expect_identical(fixture$provenance$origin, "entirely_invented")
    expect_identical(fixture$provenance$layout, "unaudited_test_layout")
  }
  expect_null(nis_synthetic_data(2017)$diagnosis_procedure_groups)
  expect_equal(nrow(nis_synthetic_data(2018)$diagnosis_procedure_groups), 12L)
  expect_identical(nis_synthetic_data(2017)$core$KEY_NIS,
                   nis_synthetic_data(2022)$core$KEY_NIS)
  expect_identical(vapply(2017:2022, function(y) {
    sum(startsWith(names(nis_synthetic_data(y)$core), "I10_DX"))
  }, integer(1)), c(2L, 3L, 4L, 2L, 3L, 4L))
})

test_that("point summaries match the hand-calculated fixture contract", {
  for (year in 2017:2022) {
    fixture <- nis_synthetic_data(year)
    core <- fixture$core
    expected <- fixture$expected
    observed_died <- !is.na(core$DIED)
    observed_age <- !is.na(core$AGE)
    expect_equal(sum(core$DISCWT), expected$weighted_discharges)
    expect_equal(sum(observed_died), expected$observed_died_discharges)
    expect_equal(sum(core$DISCWT[observed_died]), expected$observed_died_weight)
    expect_equal(sum(core$DISCWT * core$DIED, na.rm = TRUE), expected$weighted_deaths)
    expect_equal(weighted.mean(core$DIED, core$DISCWT, na.rm = TRUE),
                 expected$died_proportion_observed)
    expect_equal(sum(core$DISCWT[observed_age]), expected$observed_age_weight)
    expect_equal(weighted.mean(core$AGE, core$DISCWT, na.rm = TRUE),
                 expected$age_mean_observed)
  }
})

test_that("generation is deterministic and does not change the caller's seed", {
  set.seed(21)
  seed <- .Random.seed
  fixture <- nis_synthetic_data()
  expect_identical(.Random.seed, seed)
  expect_identical(fixture, nis_synthetic_data())
  expect_identical(fixture, nis_synthetic_data(2022))
})

test_that("invalid fixture years fail clearly", {
  for (year in list(NULL, numeric(), c(2017, 2022), 2016, 2023)) {
    expect_error(nis_synthetic_data(year), "one fixture year")
  }
  for (year in list("2022", NA_real_, Inf, 2022.5)) {
    expect_error(nis_synthetic_data(year), "whole numeric years")
  }
})
