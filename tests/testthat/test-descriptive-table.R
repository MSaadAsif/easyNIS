descriptive_spec <- function() data.frame(
  id = c("los_mean", "domain_share", "los_total"),
  field = c("LOS", "domain", "LOS"),
  statistic = c("mean", "proportion", "total"),
  label = c("Length of stay", "Domain share", "Total stays"),
  unit = c("days", "proportion", "weighted days"), stringsAsFactors = FALSE)

descriptive_table <- function(design, specification = descriptive_spec(), missing = "exclude",
                              df = 2, confidence = 0.95) {
  nis_descriptive_table(design, specification, missing, df, confidence, "wr_unadjusted")
}

descriptive_reference <- function(core, field, statistic, keep = rep(TRUE, nrow(core)), divisor = 1) {
  observed <- keep & !is.na(core[[field]])
  weights <- core$DISCWT / divisor
  denominator <- sum(weights[observed])
  estimate <- sum(weights[observed] * core[[field]][observed])
  if (statistic != "total") estimate <- estimate / denominator
  contribution <- numeric(nrow(core))
  contribution[observed] <- weights[observed] * if (statistic == "total") {
    core[[field]][observed]
  } else (core[[field]][observed] - estimate) / denominator
  hospitals <- paste(core$YEAR, core$HOSP_NIS, sep = ":")
  strata <- paste(core$YEAR, core$NIS_STRATUM, sep = ":")
  sums <- tapply(contribution, hospitals, sum)
  mapped_strata <- strata[match(names(sums), hospitals)]
  variance <- sum(vapply(split(sums, mapped_strata), function(x) {
    length(x) / (length(x) - 1) * sum((x - mean(x))^2)
  }, numeric(1)))
  c(estimate = estimate, se = sqrt(variance))
}

test_that("descriptive rows preserve scalar values and independent WR references", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$LOS[c(2, 5)] <- NA_real_
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  core[["quoted ` outcome"]] <- core$LOS
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022),
    c("LOS", "domain", "quoted ` outcome"), TRUE, "hospital_wr", "fail")
  before <- design
  result <- descriptive_table(design)
  expect_s3_class(result, "nis_descriptive_table")
  expect_false(result$provenance$analysis_ready)
  expect_identical(result$provenance$scope, "experimental_numeric_descriptive_table")
  expect_identical(result$provenance$constructor, design$provenance)
  expect_identical(result$provenance$population, design$population)
  expect_identical(result$provenance$domains, design$domains)
  expect_identical(result$data$id, descriptive_spec()$id)
  expect_identical(rownames(result$data), as.character(seq_len(nrow(result$data))))
  expect_identical(result$provenance$policies$interval_scope, "pointwise")
  expect_named(result$results, descriptive_spec()$id)
  expect_s3_class(result$results[[1]], "nis_estimate")
  expect_s3_class(result$results[[1]]$native, "svystat")
  expect_identical(result$results[[1]]$provenance$design, design$provenance)
  expect_identical(result$data$weighted_estimate, unname(vapply(result$results, `[[`, numeric(1), "estimate")))
  expect_identical(result$data$se, unname(vapply(result$results, `[[`, numeric(1), "se")))
  expect_identical(result$data$lower, unname(vapply(result$results, `[[`, numeric(1), "lower")))
  expect_identical(result$data$upper, unname(vapply(result$results, `[[`, numeric(1), "upper")))
  expect_identical(result$data$raw_missing, c(2, 0, 2))
  expect_identical(result$data$raw_supplied, rep(as.double(nrow(core)), 3))
  expect_identical(result$data$raw_included, as.double(c(nrow(core) - 2, nrow(core), nrow(core) - 2)))
  expect_identical(result$data$analysis_hospitals,
    unname(vapply(result$results, function(x) as.double(length(unique(x$design$cluster[[1]]))), numeric(1))))
  expect_true(all(result$data$disclosure_status == "unreviewed"))
  expect_identical(design, before)

  expected_mean <- descriptive_reference(core, "LOS", "mean")
  expected_total <- descriptive_reference(core, "LOS", "total")
  expected_share <- descriptive_reference(core, "domain", "proportion")
  expect_equal(c(result$data$weighted_estimate[[1]], result$data$se[[1]]), unname(expected_mean),
    tolerance = 1e-12)
  expect_equal(c(result$data$weighted_estimate[[2]], result$data$se[[2]]), unname(expected_share),
    tolerance = 1e-12)
  expect_equal(c(result$data$weighted_estimate[[3]], result$data$se[[3]]), unname(expected_total),
    tolerance = 1e-12)
  expect_equal(c(result$data$lower[[1]], result$data$upper[[1]]),
    expected_mean[[1]] + c(-1, 1) * stats::qt(0.975, 2) * expected_mean[[2]],
    tolerance = 1e-12)
  expect_equal(result$data$weighted_denominator[[1]], sum(core$DISCWT[!is.na(core$LOS)]))
})

test_that("descriptive tables retain domain and pooling intent and distinct hospital IDs", {
  session <- nis_open()
  on.exit(nis_close(session))
  designs <- lapply(2021:2022, function(year) {
    core <- nis_synthetic_data(year)$core
    core$domain <- core$HOSP_NIS %in% c("0001", "0003")
    path <- write_invented_parquet(session, core)
    on.exit(unlink(path), add = TRUE)
    nis_survey_design(nis_import(session, path, year), c("LOS", "domain"),
      TRUE, "hospital_wr", "fail")
  })
  pool <- nis_pool_design(designs, c("LOS", "domain"), "combined_total")
  spec <- data.frame(id = "total", field = "LOS", statistic = "total",
    label = "Combined stays", unit = "weighted days")
  result <- descriptive_table(pool, spec, missing = "fail")
  expect_identical(result$data$estimand, "combined_total")
  expect_equal(result$data$analysis_hospitals, 8)
  expect_identical(result$provenance$constructor, pool$provenance)
  expect_identical(result$results$total$provenance$design, pool$provenance)
  domain <- nis_domain(pool, "domain", "fail")
  domain_result <- descriptive_table(domain, spec, missing = "fail")
  expect_identical(domain_result$provenance$domains, domain$domains)
  expect_equal(domain_result$data$analysis_hospitals, 4)
  proportion_spec <- transform(spec, field = "domain", statistic = "proportion", unit = "proportion")
  pooled_proportion <- nis_pool_design(designs, c("LOS", "domain"), "pooled_proportion")
  expect_identical(descriptive_table(pooled_proportion, proportion_spec)$data$estimand,
    "weighted_pooled_proportion")
  expect_error(descriptive_table(pooled_proportion, spec), "incompatible with pooled_proportion")
})

test_that("declarations and failed scalar rows reject the complete table", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  core$zero <- 0
  core$infinite <- Inf
  core[["quoted ` outcome"]] <- core$LOS
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022),
    c("LOS", "domain", "zero", "infinite", "quoted ` outcome"), TRUE,
    "hospital_wr", "fail")
  base <- descriptive_spec()
  expect_error(descriptive_table(design, transform(base, id = c("x", "x", "z"))), "unique")
  expect_error(descriptive_table(design, transform(base, unit = c("days", "share", "days"))), "unit")
  expect_error(descriptive_table(design, transform(base, field = c("los", "domain", "LOS"))), "exactly match")
  expect_error(descriptive_table(design, transform(base, statistic = c("median", "proportion", "total"))), "statistics")
  expect_error(descriptive_table(design, transform(base, label = c("", "share", "total"))), "nonmissing, nonempty")
  duplicate_columns <- base
  names(duplicate_columns)[[5L]] <- "id"
  expect_error(descriptive_table(design, duplicate_columns), "exactly")
  extra_column <- base
  extra_column$extra <- "extra"
  expect_error(descriptive_table(design, extra_column), "exactly")
  expect_error(descriptive_table(design, base[, 1:4]), "exactly")
  expect_error(descriptive_table(design, as.data.frame(lapply(base, factor))), "character")
  expect_error(descriptive_table(design, transform(base, field = c("LOS", "domain", "infinite"))), "Infinite outcomes")
  expect_error(nis_descriptive_table(design, base, "exclude", 0, 0.95, "wr_unadjusted"), "positive numeric")
  expect_error(nis_descriptive_table(design, base, "exclude", Inf, 1, "wr_unadjusted"), "strictly between")
  expect_error(nis_descriptive_table(design, base, "exclude", 2, 0.95, "adjusted"), "variance =")
  saved_options <- options(survey.lonely.psu = "adjust")
  on.exit(options(saved_options), add = TRUE)
  expect_error(descriptive_table(design, base), "current survey.lonely.psu")
  expect_identical(getOption("survey.lonely.psu"), "adjust")
  options(saved_options)
  quoted <- transform(base[1, ], field = "quoted ` outcome")
  expect_equal(descriptive_table(design, quoted)$data$weighted_estimate,
    nis_estimate(design, "quoted ` outcome", "mean", "exclude", 2, 0.95,
      "wr_unadjusted")$estimate)
  zero <- transform(base[1, ], field = "zero", statistic = "mean", unit = "count")
  expect_identical(unlist(descriptive_table(design, zero)$data[c("weighted_estimate", "se", "lower", "upper")]),
    c(weighted_estimate = 0, se = 0, lower = 0, upper = 0))
  normal <- descriptive_table(design, transform(base[3, ], field = "LOS"), df = Inf)
  expect_identical(normal$data$df, Inf)
  expect_identical(normal$results[[1]]$df, Inf)
})
