test_that("explicit pooled estimands preserve year-specific PSUs and reference arithmetic", {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  cores <- lapply(2021:2022, function(year) {
    core <- nis_synthetic_data(year)$core
    core$domain <- core$HOSP_NIS %in% c("0001", "0003")
    if (year == 2022L) {
      core$DISCWT <- 2 * core$DISCWT
      core$LOS <- rep(c(1L, 2L, 5L), 4L)
    }
    core
  })
  designs <- lapply(cores, function(core) {
    path <- write_invented_parquet(session, core)
    paths <<- c(paths, path)
    data <- nis_import(session, path, core$YEAR[1L])
    nis_survey_design(data, c("domain", "LOS", "AGE"), TRUE, "hospital_wr", "fail")
  })
  options_before <- options()
  combined <- nis_pool_design(designs, c("domain", "LOS", "AGE"), "combined_total")
  average <- nis_pool_design(designs, c("domain", "LOS", "AGE"), "average_annual_total")
  proportion <- nis_pool_design(designs, c("domain", "LOS", "AGE"), "pooled_proportion")
  expect_identical(options(), options_before)
  expect_equal(combined$population, list(discharges = 24L, hospitals = 8L,
    strata = 4L, degrees_of_freedom = 4, singleton_strata = 0L))
  expect_identical(combined$provenance$years, 2021:2022)
  expect_equal(combined$provenance$weight_divisor, 1)
  expect_equal(average$provenance$weight_divisor, 2)
  expect_identical(combined$annual_designs, designs)
  expect_false(combined$provenance$analysis_ready)
  expect_equal(sum(stats::weights(combined$design)), 108)
  expect_equal(sum(stats::weights(average$design)), 54)
  expect_equal(stats::weights(proportion$design), stats::weights(combined$design))
  domain <- nis_domain(combined, "domain", "fail")
  average_domain <- nis_domain(average, "domain", "fail")
  # Domain hospital contributions are 22,22 in 2021 and 56,56 in 2022.
  total <- survey::svytotal(~LOS, domain$design)
  average_total <- survey::svytotal(~LOS, average_domain$design)
  mean <- survey::svymean(~LOS, domain$design)
  expect_equal(unname(stats::coef(total)), 156, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(total)), matrix(2 * 22^2 + 2 * 56^2), tolerance = 1e-12)
  expect_equal(unname(stats::coef(average_total)), 78, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(average_total)), matrix((2 * 22^2 + 2 * 56^2) / 4), tolerance = 1e-12)
  expect_equal(unname(stats::coef(mean)), 156 / 54, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(mean)), matrix(64 / 54^2), tolerance = 1e-12)
  expect_equal(stats::coef(survey::svymean(~LOS, average_domain$design)), stats::coef(mean), tolerance = 1e-12)
  expect_equal(stats::vcov(survey::svymean(~LOS, average_domain$design)), stats::vcov(mean), tolerance = 1e-12)
  p <- survey::svymean(~domain, proportion$design)
  expect_equal(unname(stats::coef(p)[2L]), 0.5, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(p)[2L, 2L]), 810 / 108^2, tolerance = 1e-12)
  reference_fields <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "domain", "LOS", "AGE")
  reference_rows <- do.call(rbind, lapply(cores, function(core) core[, reference_fields]))
  reference_rows$psu_year <- interaction(reference_rows$YEAR, reference_rows$HOSP_NIS, drop = TRUE)
  reference_rows$stratum_year <- interaction(reference_rows$YEAR, reference_rows$NIS_STRATUM, drop = TRUE)
  reference <- survey::svydesign(ids = ~psu_year, strata = ~stratum_year,
    weights = ~DISCWT, data = reference_rows, nest = TRUE)
  reference_domain <- subset(reference, domain)
  expected <- survey::svytotal(~LOS, reference_domain)
  expect_equal(stats::coef(total), stats::coef(expected), tolerance = 1e-12)
  expect_equal(stats::vcov(total), stats::vcov(expected), tolerance = 1e-12)
  estimate_age <- survey::svymean(~AGE, combined$design, na.rm = TRUE)
  reference_age <- survey::svymean(~AGE, reference, na.rm = TRUE)
  expect_equal(stats::coef(estimate_age), stats::coef(reference_age), tolerance = 1e-12)
  expect_equal(stats::vcov(estimate_age), stats::vcov(reference_age), tolerance = 1e-12)
  expect_equal(sum(is.na(combined$design$variables$AGE)), 2)
  expect_identical(combined$design$variables$DISCWT, reference_rows$DISCWT)
  expect_equal(domain$domains[[1L]]$included, 12)
  expect_error(nis_pool_design(list(domain, designs[[2L]]), "LOS", "combined_total"), "before selecting domains")
  expect_error(nis_pool_design(list(combined, designs[[2L]]), "LOS", "combined_total"), "single-year")
  expect_error(nis_pool_design(list(designs[[1L]], designs[[1L]]), "LOS", "combined_total"), "distinct year")
  expect_error(nis_pool_design(designs, "LOS"), "explicit")
  expect_error(nis_pool_design(designs, "ABSENT", "combined_total"), "every annual design")
  expect_error(nis_pool_design(designs, character(), "combined_total"), "unique non-empty")
  expect_error(nis_pool_design(designs, "LOS", "unknown"), "arg")
  expect_error(nis_pool_design(list(designs[[1L]]), "LOS", "combined_total"), "at least two")
})

test_that("pooled projection preserves exact raw identifiers and rejects incompatible fields", {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  designs <- lapply(2021:2022, function(year) {
    core <- nis_synthetic_data(year)$core
    core$HOSP_NIS <- DBI::dbGetQuery(session$connection,
      "SELECT CAST(9007199254741001 + CAST(floor(i / 3) AS BIGINT) AS BIGINT) AS id FROM range(12) t(i)")$id
    core$label <- factor(rep(c("A", "B"), 6L))
    path <- write_invented_parquet(session, core)
    paths <<- c(paths, path)
    data <- nis_import(session, path, year)
    nis_survey_design(data, c("LOS", "label"), TRUE, "hospital_wr", "fail")
  })
  pooled <- nis_pool_design(designs, "LOS", "combined_total")
  expect_equal(pooled$population$hospitals, 8)
  expect_identical(pooled$design$variables$HOSP_NIS,
    rep(as.character(designs[[1L]]$design$variables$HOSP_NIS), 2L))
  expect_s3_class(pooled$annual_designs[[1L]]$design$variables$HOSP_NIS, "integer64")
  incompatible <- designs
  incompatible[[2L]]$design$variables$LOS <- as.double(incompatible[[2L]]$design$variables$LOS)
  expect_error(nis_pool_design(incompatible, "LOS", "combined_total"), "classes differ")
  factor_designs <- designs
  factor_designs[[1L]]$design$variables$label <- factor(
    factor_designs[[1L]]$design$variables$label, levels = c("A", "B"))
  factor_designs[[2L]]$design$variables$label <- factor(
    factor_designs[[2L]]$design$variables$label, levels = c("B", "A"))
  expect_error(nis_pool_design(factor_designs, "label", "combined_total"), "factor levels differ")
  nis_close(session)
  expect_equal(nrow(pooled$design$variables), 24)
})
