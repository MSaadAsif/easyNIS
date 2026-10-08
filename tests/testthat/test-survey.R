prepare_invented_design <- function(data, columns) {
  nis_survey_design(data, columns, full_population = TRUE,
                     method = "hospital_wr", singleton = "fail")
}

test_that("full designs and zero-hospital domains match independent WR calculations", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$LOS[7:9] <- c(3L, 1L, 5L)
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  core$zero <- 0
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  expect_true(requireNamespace("survey", quietly = TRUE))
  options_before <- options()
  design <- prepare_invented_design(data, c("LOS", "AGE", "domain", "zero"))
  expect_s3_class(design$design, "survey.design2")
  expect_identical(names(design$design$variables),
    c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "LOS", "AGE", "domain", "zero"))
  expect_equal(design$population, list(discharges = 12L, hospitals = 4L,
    strata = 2L, degrees_of_freedom = 2, singleton_strata = 0L))
  expect_false(design$provenance$analysis_ready)
  expect_identical(design$provenance$full_population, "caller_declared_unverified")
  expect_identical(design$provenance$sources, data$sources)
  expect_identical(design$provenance$component_schemas, data$component_schemas)
  expect_identical(design$provenance$initial_survey_options,
    options()[grepl("^survey[.]", names(options()))])
  expect_equal(sum(is.na(design$design$variables$AGE)), 1)
  expect_identical(design$design$variables$KEY_NIS,
    core$KEY_NIS[match(design$design$variables$KEY_NIS, core$KEY_NIS)])
  reference <- survey::svydesign(ids = ~HOSP_NIS, strata = ~NIS_STRATUM,
    weights = ~DISCWT, data = core, nest = TRUE)
  domain <- nis_domain(design, "domain", "fail")
  reference_domain <- subset(reference, domain)
  expect_identical(options(), options_before)
  for (statistic in c("svytotal", "svymean")) {
    estimate <- getExportedValue("survey", statistic)(~LOS, domain$design)
    expected <- getExportedValue("survey", statistic)(~LOS, reference_domain)
    expect_equal(unname(stats::coef(estimate)), unname(stats::coef(expected)), tolerance = 1e-12)
    expect_equal(unname(stats::vcov(estimate)), unname(stats::vcov(expected)), tolerance = 1e-12)
  }
  total <- survey::svytotal(~LOS, domain$design)
  mean <- survey::svymean(~LOS, domain$design)
  count <- survey::svytotal(~domain, design$design)
  # Each stratum has two hospitals; absent-domain hospital contributions are zero.
  # Weighted LOS totals are 22 and 29, and domain weights are 9 and 9.
  expect_equal(unname(stats::coef(total)), 51, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(total)), matrix(22^2 + 29^2), tolerance = 1e-12)
  expect_equal(unname(stats::coef(mean)), 51 / 18, tolerance = 1e-12)
  expect_equal(unname(stats::vcov(mean)), matrix((3.5^2 + 3.5^2) / 18^2), tolerance = 1e-12)
  expect_equal(unname(stats::coef(count)[2L]), 18)
  expect_equal(unname(stats::vcov(count)[2L, 2L]), 9^2 + 9^2)
  expect_equal(domain$design$fpc$sampsize, reference_domain$fpc$sampsize)
  expect_identical(domain$population, design$population)
  expect_equal(domain$domains[[1L]], list(field = "domain", missing = "fail",
    supplied = 12L, included = 6L, excluded_false = 6L, unknown = 0L))
  zero <- survey::svytotal(~zero, domain$design)
  expect_equal(unname(stats::coef(zero)), 0)
  expect_equal(unname(stats::vcov(zero)), matrix(0))
  nis_close(session)
  expect_equal(unname(stats::coef(survey::svytotal(~LOS, domain$design))), 51)
})

test_that("domain missingness, empty domains and repeated selection are explicit", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$domain <- rep(c(TRUE, FALSE, NA), 4L)
  core$empty <- FALSE
  core$numeric_flag <- as.integer(core$domain)
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  data <- nis_import(session, path, 2022)
  design <- prepare_invented_design(data, c("domain", "empty", "numeric_flag", "AGE"))
  expect_error(nis_domain(design, "domain"), "explicit")
  expect_error(nis_domain(design, "domain", c("fail", "exclude")), "string")
  expect_error(nis_domain(design, "domain", "fail"), "unknown")
  domain <- nis_domain(design, "domain", "exclude")
  expect_equal(domain$domains[[1L]]$included, 4)
  expect_equal(domain$domains[[1L]]$unknown, 4)
  expect_equal(domain$domains[[1L]]$excluded_false, 4)
  repeated <- nis_domain(domain, "empty", "fail")
  expect_equal(nrow(repeated$design$variables), 0)
  expect_length(repeated$domains, 2L)
  expect_equal(repeated$domains[[2L]]$supplied, 4)
  expect_identical(repeated$population, design$population)
  expect_equal(nrow(design$design$variables), 12)
  expect_error(nis_domain(design, "numeric_flag", "exclude"), "logical")
  expect_error(nis_domain(design, "not_retained", "exclude"), "not retained")
  expect_error(nis_domain(data, "domain", "exclude"), "must come from")
  reference <- survey::svydesign(ids = ~HOSP_NIS, strata = ~NIS_STRATUM,
    weights = ~DISCWT, data = core, nest = TRUE)
  estimate <- survey::svymean(~AGE, design$design, na.rm = TRUE)
  expected <- survey::svymean(~AGE, reference, na.rm = TRUE)
  expect_equal(stats::coef(estimate), stats::coef(expected), tolerance = 1e-12)
  expect_equal(stats::vcov(estimate), stats::vcov(expected), tolerance = 1e-12)
  expect_equal(unname(stats::coef(estimate)), 42.5, tolerance = 1e-12)
})

test_that("design declarations, structural rejection and exact large identifiers are enforced", {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  import_core <- function(core) {
    path <- write_invented_parquet(session, core)
    paths <<- c(paths, path)
    nis_import(session, path, 2022)
  }
  core <- nis_synthetic_data()$core
  data <- import_core(core)
  expect_error(nis_survey_design(data, "AGE"), "full_population")
  expect_error(nis_survey_design(data, "AGE", FALSE, "hospital_wr", "fail"), "prefiltered")
  expect_error(nis_survey_design(data, "AGE", TRUE, "unknown", "fail"), "other designs")
  expect_error(nis_survey_design(data, "AGE", TRUE, "hospital_wr", "adjust"), "other policies")
  expect_error(prepare_invented_design(nis_select(data, "AGE"), "AGE"), "lacks required")
  for (weight in list(NA_real_, 0, -1, Inf, NaN, "2")) {
    invalid <- core
    invalid$DISCWT <- rep(weight, nrow(core))
    expect_error(prepare_invented_design(import_core(invalid), "AGE"), "structurally valid")
  }
  tiny <- core
  tiny$DISCWT <- rep(1e-320, nrow(core))
  expect_error(prepare_invented_design(import_core(tiny), "AGE"), "finite native")
  conflicting <- core
  conflicting$NIS_STRATUM[1L] <- 2L
  old_options <- options(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE)
  on.exit(options(old_options), add = TRUE)
  options_before <- options()
  expect_error(prepare_invented_design(import_core(conflicting), "AGE"), "multiple strata")
  singleton <- core
  singleton$NIS_STRATUM <- rep(c(1L, 2L, 2L, 2L), each = 3L)
  expect_error(prepare_invented_design(import_core(singleton), "AGE"), "Singleton")
  expect_identical(options(), options_before)
  large <- core
  large$HOSP_NIS <- paste0("900719925474", rep(1001:1004, each = 3L))
  exact <- prepare_invented_design(import_core(large), "AGE")
  expect_equal(exact$population$hospitals, 4L)
  expect_setequal(as.character(exact$design$variables$HOSP_NIS), large$HOSP_NIS)
  bigint <- core
  bigint$HOSP_NIS <- DBI::dbGetQuery(session$connection,
    "SELECT CAST(9007199254741001 + CAST(floor(i / 3) AS BIGINT) AS BIGINT) AS id FROM range(12) t(i)")$id
  bigint$DISCWT <- DBI::dbGetQuery(session$connection,
    "SELECT CAST(2 + i % 3 AS BIGINT) AS weight FROM range(12) t(i)")$weight
  bigint_design <- prepare_invented_design(import_core(bigint), "AGE")
  expect_equal(bigint_design$population$hospitals, 4L)
  expect_s3_class(bigint_design$design$variables$HOSP_NIS, "integer64")
  expect_equal(sum(stats::weights(bigint_design$design)), 36)
  expect_s3_class(bigint_design$design$variables$DISCWT, "integer64")
  unsafe <- bigint
  unsafe$DISCWT <- DBI::dbGetQuery(session$connection,
    "SELECT CAST(9007199254740993 AS BIGINT) AS weight FROM range(12)")$weight
  expect_error(prepare_invented_design(import_core(unsafe), "AGE"), "exact double range")
  mixed <- core
  mixed$YEAR[1L] <- 2021L
  expect_error(import_core(mixed), "YEAR")
  nis_close(session)
  expect_error(prepare_invented_design(data, "AGE"), "closed")
})
