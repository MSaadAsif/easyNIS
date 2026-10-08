prepare_estimate_design <- function(data, columns) {
  nis_survey_design(data, columns, TRUE, "hospital_wr", "fail")
}

estimate_invented <- function(design, field, statistic = "mean", missing = "fail",
                              df = 2, confidence = 0.95) {
  nis_estimate(design, field, statistic, missing, df, confidence, "wr_unadjusted")
}

# Independent WR arithmetic sums contributions across every original hospital,
# including zero contributions outside the domain or after outcome exclusion.
reference_wr <- function(core, field, statistic, keep = rep(TRUE, nrow(core)), divisor = 1) {
  weights <- core$DISCWT / divisor
  included <- keep & !is.na(core[[field]])
  denominator <- sum(weights[included])
  total <- sum(weights[included] * core[[field]][included])
  estimate <- if (statistic == "total") total else total / denominator
  contribution <- numeric(nrow(core))
  contribution[included] <- weights[included] * if (statistic == "total") {
    core[[field]][included]
  } else (core[[field]][included] - estimate) / denominator
  hospitals <- paste(core$YEAR, core$HOSP_NIS, sep = ":")
  strata <- paste(core$YEAR, core$NIS_STRATUM, sep = ":")
  totals <- tapply(contribution, hospitals, sum)
  hospital_strata <- strata[match(names(totals), hospitals)]
  variance <- sum(vapply(split(totals, hospital_strata), function(x) {
    length(x) / (length(x) - 1) * sum((x - mean(x))^2)
  }, numeric(1)))
  c(estimate = estimate, se = sqrt(variance))
}

test_that("scalar estimates and intervals match independent full and sparse-domain arithmetic", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$LOS[7:9] <- c(3L, 1L, 5L)
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  core$sparse <- seq_len(nrow(core)) == 1L
  core$zero <- 0
  core$one <- TRUE
  core[["quoted ` outcome + stop('injected')"]] <- core$LOS
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- prepare_estimate_design(nis_import(session, path, 2022),
    c("LOS", "domain", "sparse", "zero", "one", "quoted ` outcome + stop('injected')"))
  before <- design
  for (selected in list(design, nis_domain(design, "domain", "fail"),
                        nis_domain(design, "sparse", "fail"))) {
    keep <- core$KEY_NIS %in% as.character(selected$design$variables$KEY_NIS)
    for (statistic in c("total", "mean", "proportion")) {
      field <- if (statistic == "proportion") "domain" else "LOS"
      expected <- reference_wr(core, field, statistic, keep)
      result <- estimate_invented(selected, field, statistic)
      expect_s3_class(result, "nis_estimate")
      expect_s3_class(result$native, "svystat")
      expect_equal(c(estimate = result$estimate, se = result$se), expected, tolerance = 1e-12)
      expect_equal(c(result$lower, result$upper), expected[1L] + c(-1, 1) *
        stats::qt(0.975, 2) * expected[2L], tolerance = 1e-12)
      expect_identical(result$provenance$design, selected$provenance)
      expect_identical(result$provenance$domains, selected$domains)
      expect_identical(result$provenance$population, selected$population)
      expect_equal(result$sample$full_population_degrees_of_freedom, 2)
      expect_equal(result$sample$analysis_degrees_of_freedom, survey::degf(selected$design))
      expect_false(result$provenance$analysis_ready)
    }
  }
  sparse <- estimate_invented(nis_domain(design, "sparse", "fail"), "LOS", "total", df = Inf,
                              confidence = 0.9)
  expect_equal(sparse$sample$domain_degrees_of_freedom, 0)
  expect_equal(sparse$df, Inf)
  domain <- nis_domain(design, "domain", "fail")
  normal <- estimate_invented(domain, "LOS", "total", df = Inf, confidence = 0.9)
  expect_equal(normal$estimate, 51)
  expect_equal(normal$se, sqrt(22^2 + 29^2))
  expect_equal(c(normal$lower, normal$upper), 51 + c(-1, 1) * stats::qnorm(0.95) * normal$se)
  expect_equal(estimate_invented(domain, "quoted ` outcome + stop('injected')", "total")$estimate, 51)
  for (statistic in c("total", "mean", "proportion")) {
    zero <- estimate_invented(domain, "zero", statistic)
    expect_equal(c(zero$estimate, zero$se, zero$lower, zero$upper), rep(0, 4L))
  }
  one <- estimate_invented(domain, "one", "proportion")
  expect_equal(c(one$estimate, one$se, one$lower, one$upper), c(1, 0, 1, 1))
  expect_identical(design, before)
})

test_that("outcome exclusion preserves original hospitals, raw sentinels and sample accounting", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  # Three hospitals in stratum one, two in stratum two. Entire hospitals and
  # then an entire stratum lack observed outcomes; native PSU sizes must remain.
  core$HOSP_NIS <- c("1", "1", "2", "2", "3", "3", "4", "4", "5", "5", "5", "5")
  core$outcome <- c(2, 4, NA, NaN, 1, -9, NA, NA, NA, NA, NA, NA)
  core$domain <- rep(c(TRUE, TRUE, FALSE), 4)
  core$all_missing <- NA_real_
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- prepare_estimate_design(nis_import(session, path, 2022),
    c("outcome", "domain", "all_missing"))
  expect_error(estimate_invented(design, "outcome"), "NA or NaN")
  for (selected in list(design, nis_domain(design, "domain", "fail"))) {
    keep <- core$KEY_NIS %in% as.character(selected$design$variables$KEY_NIS)
    for (statistic in c("total", "mean")) {
      result <- estimate_invented(selected, "outcome", statistic, "exclude", df = 7)
      expect_equal(c(estimate = result$estimate, se = result$se),
        reference_wr(core, "outcome", statistic, keep), tolerance = 1e-12)
      expected_design <- selected$design[!is.na(selected$design$variables$outcome), ]
      expect_equal(result$design$fpc$sampsize, expected_design$fpc$sampsize)
      expect_equal(result$sample$included, sum(keep & !is.na(core$outcome)))
      expect_equal(result$sample$excluded_missing, sum(keep & is.na(core$outcome)))
      expect_equal(result$sample$supplied, sum(keep))
      expect_equal(result$df, 7)
      expect_equal(result$sample$weighted_denominator, sum(core$DISCWT[keep & !is.na(core$outcome)]))
    }
  }
  expect_true(-9 %in% design$design$variables$outcome)
  expect_error(estimate_invented(design, "all_missing", missing = "exclude"), "empty analysis")
})

test_that("pooled estimates retain reused annual IDs and constructor intent", {
  session <- nis_open()
  on.exit(nis_close(session))
  paths <- character()
  on.exit(unlink(paths), add = TRUE)
  cores <- lapply(2021:2022, function(year) {
    core <- nis_synthetic_data(year)$core
    core$domain <- core$HOSP_NIS %in% c("0001", "0003")
    if (year == 2022) {
      core$DISCWT <- 2 * core$DISCWT
      core$LOS <- rep(c(1L, 2L, 5L), 4L)
    }
    core
  })
  designs <- lapply(cores, function(core) {
    path <- write_invented_parquet(session, core)
    paths <<- c(paths, path)
    prepare_estimate_design(nis_import(session, path, core$YEAR[1L]), c("LOS", "AGE", "domain"))
  })
  reference_fields <- c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "LOS", "AGE", "domain")
  rows <- do.call(rbind, lapply(cores, function(core) core[, reference_fields]))
  for (intent in c("combined_total", "average_annual_total", "pooled_proportion")) {
    pool <- nis_pool_design(designs, c("LOS", "AGE", "domain"), intent)
    divisor <- if (intent == "average_annual_total") 2 else 1
    if (intent == "pooled_proportion") {
      expect_error(estimate_invented(pool, "LOS", "total"), "incompatible")
    } else {
      result <- estimate_invented(nis_domain(pool, "domain", "fail"), "LOS", "total")
      expect_equal(c(estimate = result$estimate, se = result$se),
        reference_wr(rows, "LOS", "total", rows$domain, divisor), tolerance = 1e-12)
      expect_identical(result$estimand, intent)
    }
    for (statistic in c("mean", "proportion")) {
      field <- if (statistic == "mean") "AGE" else "domain"
      result <- estimate_invented(pool, field, statistic, "exclude")
      expect_equal(c(estimate = result$estimate, se = result$se),
        reference_wr(rows, field, statistic, divisor = divisor), tolerance = 1e-12)
      expect_identical(result$estimand, paste0("weighted_pooled_", statistic))
      expect_equal(result$sample$full_population_degrees_of_freedom, 4)
      expect_identical(result$provenance$design$annual_provenance, pool$provenance$annual_provenance)
    }
  }
})

test_that("BIGINT outcomes convert exactly and invalid parameters/options are refused", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$exact <- DBI::dbGetQuery(session$connection,
    "SELECT CAST(CASE WHEN i=0 THEN 9007199254740991 WHEN i=1 THEN -9007199254740991 ELSE 0 END AS BIGINT) x FROM range(12) t(i)")$x
  core$unsafe <- DBI::dbGetQuery(session$connection,
    "SELECT CAST(-9007199254740993 AS BIGINT) x FROM range(12)")$x
  core$empty <- FALSE
  core$infinite <- Inf
  core$text <- "1"
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- prepare_estimate_design(nis_import(session, path, 2022),
    c("exact", "unsafe", "empty", "infinite", "text", "LOS"))
  result <- estimate_invented(design, "exact", "total")
  numeric_core <- core
  numeric_core$exact <- as.double(as.character(core$exact))
  expect_equal(c(estimate = result$estimate, se = result$se), reference_wr(numeric_core, "exact", "total"), tolerance = 1e-12)
  expect_s3_class(result$design$variables$exact, "integer64")
  expect_identical(result$design$variables$exact, design$design$variables$exact)
  expect_error(estimate_invented(design, "unsafe"), "exact double range")
  expect_error(estimate_invented(design, "infinite", missing = "exclude"), "Infinite")
  expect_error(estimate_invented(design, "text"), "plain numeric")
  factor_design <- design
  factor_design$design$variables$text <- factor(rep(c("0", "1"), 6))
  expect_error(estimate_invented(factor_design, "text"), "plain numeric")
  complex_design <- design
  complex_design$design$variables$text <- rep(1 + 2i, 12)
  expect_error(estimate_invented(complex_design, "text"), "plain numeric")
  overflow_design <- design
  overflow_design$design$prob <- rep(1e-308, 12)
  expect_error(estimate_invented(overflow_design, "LOS"), "denominator")
  expect_error(estimate_invented(nis_domain(design, "empty", "fail"), "LOS"), "empty analysis")
  expect_error(estimate_invented(design, "LOS", "proportion"), "zero/one")
  expect_error(estimate_invented(design, "ABSENT"), "not retained")
  expect_error(estimate_invented(list(), "LOS"), "nis_survey")
  expect_error(nis_estimate(design, "LOS"), "explicit")
  expect_error(nis_estimate(design, "LOS", "mean", "fail", 2, 0.95), "explicit")
  for (df in list(0, -1, -Inf, NA_real_, NaN, "2", TRUE, 1 + 2i, numeric(), c(1, 2))) {
    expect_error(estimate_invented(design, "LOS", df = df), "positive numeric scalar")
  }
  for (confidence in list(0, 1, Inf, NA_real_, NaN, "0.95", TRUE, 0.9 + 2i, numeric(), c(0.9, 0.95))) {
    expect_error(estimate_invented(design, "LOS", confidence = confidence), "strictly between")
  }
  expect_error(estimate_invented(design, "LOS", "unknown"), "Choose total")
  expect_error(estimate_invented(design, "LOS", missing = "unknown"), "Choose total")
  expect_error(nis_estimate(design, "LOS", "mean", "fail", 2, 0.95, "adjust"), "wr_unadjusted")
  for (settings in list(list(survey.lonely.psu = "adjust"),
                        list(survey.adjust.domain.lonely = TRUE),
                        list(survey.lonely.psu = NULL))) {
    previous <- options(settings)
    snapshot <- options()
    expect_error(estimate_invented(design, "LOS"), "requires current")
    expect_identical(options(), snapshot)
    options(previous)
  }
  previous <- options(survey.ultimate.cluster = TRUE, survey.use_rcpp = FALSE)
  on.exit(options(previous), add = TRUE)
  snapshot <- options()
  result <- estimate_invented(design, "LOS")
  expect_equal(c(estimate = result$estimate, se = result$se), reference_wr(core, "LOS", "mean"), tolerance = 1e-12)
  expect_identical(result$provenance$current_survey_options,
    snapshot[grepl("^survey[.]", names(snapshot))])
  expect_identical(options(), snapshot)
})
