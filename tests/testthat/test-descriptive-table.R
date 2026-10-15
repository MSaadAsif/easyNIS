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
  expect_identical(result, nis_descriptive_table(design, descriptive_spec(), "exclude", 2,
    0.95, "wr_unadjusted", by = NULL, group_missing = NULL))
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
    core$group_source <- ifelse(core$HOSP_NIS %in% c("0001", "0002"), "B", "A")
    path <- write_invented_parquet(session, core)
    on.exit(unlink(path), add = TRUE)
    design <- nis_survey_design(nis_import(session, path, year), c("LOS", "domain", "group_source"),
      TRUE, "hospital_wr", "fail")
    nis_factor(design, "group_source", "group_factor", c("B", "A", "unused"),
      c("Beta", "Alpha", "Unused"))
  })
  pool <- nis_pool_design(designs, c("LOS", "domain", "group_factor"), "combined_total")
  spec <- data.frame(id = "total", field = "LOS", statistic = "total",
    label = "Combined stays", unit = "weighted days")
  result <- descriptive_table(pool, spec, missing = "fail")
  expect_identical(result$data$estimand, "combined_total")
  expect_equal(result$data$analysis_hospitals, 8)
  expect_identical(result$provenance$constructor, pool$provenance)
  expect_identical(result$results$total$provenance$design, pool$provenance)
  grouped_spec <- transform(spec, id = "group_total")
  grouped <- nis_descriptive_table(pool, grouped_spec, "fail", 2, 0.95,
    "wr_unadjusted", by = "group_factor", group_missing = "fail")
  expect_identical(grouped$data$id, c("g1.group_total", "g2.group_total"))
  expect_equal(grouped$data$analysis_hospitals, c(4, 4))
  expect_identical(grouped$results[[1L]]$provenance$design, pool$provenance)
  expect_equal(grouped$data$weighted_estimate,
    unname(vapply(c("Beta", "Alpha"), function(level) {
      domain <- nis_domain(pool,
        stats::as.formula(call("~", call("==", as.name("group_factor"), level)), env = baseenv()),
        "fail")
      nis_descriptive_table(domain, grouped_spec, "fail", 2, 0.95,
        "wr_unadjusted")$data$weighted_estimate[[1L]]
    }, numeric(1))))
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

test_that("grouped numeric tables use ordered factor domains and retain native estimates", {
  session <- nis_open()
  on.exit(nis_close(session))
  core <- nis_synthetic_data()$core
  core$LOS[c(2, 5)] <- NA_real_
  core$group_source <- ifelse(core$HOSP_NIS %in% c("0001", "0002"), "B", "A")
  core$group_source[c(1, 4)] <- NA_character_
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  path <- write_invented_parquet(session, core)
  on.exit(unlink(path), add = TRUE)
  design <- nis_survey_design(nis_import(session, path, 2022),
    c("LOS", "group_source", "domain"), TRUE, "hospital_wr", "fail")
  odd_level <- "A'`\\ | system()"
  factored <- nis_factor(design, "group_source", "group `field", c("B", "A", "unused"),
    c("Beta", odd_level, "Unused"))
  spec <- data.frame(id = c("mean", "share", "total"),
    field = c("LOS", "domain", "LOS"), statistic = c("mean", "proportion", "total"),
    label = c("Mean", "Share", "Total"), unit = c("days", "proportion", "days"))
  caller_before <- factored
  result <- nis_descriptive_table(factored, spec, "exclude", 2, 0.95,
    "wr_unadjusted", by = "group `field", group_missing = "exclude")
  expect_identical(factored, caller_before)
  expect_identical(result$data$id,
    c("g1.mean", "g1.share", "g1.total", "g2.mean", "g2.share", "g2.total"))
  expect_identical(result$data$label[[1]], "Mean | group `field = Beta")
  expect_identical(result$provenance$grouping,
    list(field = "group `field", observed_levels = c("Beta", odd_level),
      unused_levels = "Unused", unknown = 2, missing = "exclude"))
  expect_identical(names(result$results), result$data$id)
  expected_missing <- unlist(lapply(c("B", "A"), function(level) {
    selected <- !is.na(core$group_source) & core$group_source == level
    vapply(spec$field, function(field) as.double(sum(selected & is.na(core[[field]]))), numeric(1))
  }), use.names = FALSE)
  expect_identical(result$data$raw_missing, expected_missing)
  expect_identical(result$provenance$population, factored$population)
  expect_identical(result$provenance$domains, factored$domains)
  current_domain <- nis_domain(factored, "domain", "fail")
  domain_grouped <- nis_descriptive_table(current_domain, spec, "exclude", 2, 0.95,
    "wr_unadjusted", by = "group `field", group_missing = "exclude")
  expect_identical(domain_grouped$provenance$grouping$unknown,
    as.double(sum(is.na(current_domain$design$variables[["group `field"]]))))
  expect_identical(domain_grouped$provenance$population, factored$population)
  expect_identical(domain_grouped$results[[1L]]$provenance$domains[[1L]], current_domain$domains[[1L]])
  for (g in seq_along(c("Beta", odd_level))) {
    level <- c("Beta", odd_level)[[g]]
    domain <- nis_domain(factored,
      stats::as.formula(call("~", call("==", as.name("group `field"), level)), env = baseenv()),
      "exclude")
    standalone <- nis_descriptive_table(domain, spec, "exclude", 2, 0.95, "wr_unadjusted")
    rows <- ((g - 1L) * nrow(spec) + 1L):(g * nrow(spec))
    expect_identical(result$data$weighted_estimate[rows], standalone$data$weighted_estimate)
    expect_identical(result$data$se[rows], standalone$data$se)
    expect_identical(result$results[[rows[[1L]]]]$provenance$domains, domain$domains)
    expect_s3_class(result$results[[rows[[1L]]]]$native, "svystat")
  }
  for (g in seq_along(c("B", "A"))) {
    selected <- !is.na(core$group_source) & core$group_source == c("B", "A")[[g]]
    expect_gt(length(unique(core$HOSP_NIS)), length(unique(core$HOSP_NIS[selected])))
    rows <- ((g - 1L) * nrow(spec) + 1L):(g * nrow(spec))
    for (j in seq_len(nrow(spec))) {
      ref <- descriptive_reference(core, spec$field[[j]], spec$statistic[[j]], selected)
      expect_equal(c(result$data$weighted_estimate[[rows[[j]]]], result$data$se[[rows[[j]]]]),
        unname(ref), tolerance = 1e-12)
    }
  }
  expect_error(nis_disclosure_review(result, c(1, 10), "display", 1, list()),
    "Grouped descriptive tables")
  expect_error(nis_disclosure_review(result, c(1, 10), "display", 1,
    list(list(total = "g1.mean", parts = c("g2.mean")))), "Grouped descriptive tables")
  expect_error(nis_descriptive_table(factored, spec, "exclude", 2, 0.95,
    "wr_unadjusted", by = "group `field", group_missing = "fail"), "missing membership")
  expect_error(nis_descriptive_table(factored, spec, "exclude", 2, 0.95,
    "wr_unadjusted", by = "group `field", group_missing = "f"), "exactly")
  expect_error(nis_descriptive_table(factored, spec, "exclude", 2, 0.95,
    "wr_unadjusted", group_missing = "exclude"), "requires `by`")
  expect_error(nis_descriptive_table(factored, spec, "exclude", 2, 0.95,
    "wr_unadjusted", by = "group_source", group_missing = "exclude"), "standard unordered factor")
  for (bad_levels in list(c("Beta", ""), c("Beta", NA_character_), c("Beta", "Beta"))) {
    malformed <- factored
    malformed$design$variables[["group `field"]] <- structure(
      rep(1L, nrow(malformed$design$variables)), levels = bad_levels, class = "factor")
    expect_error(nis_descriptive_table(malformed, spec[1L, ], "exclude", 2,
      0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
      "Grouping factor levels")
  }
  named_levels <- c("Beta", "Alpha")
  names(named_levels) <- c("first", "second")
  malformed_levels <- factored
  malformed_levels$design$variables[["group `field"]] <- structure(
    rep(1L, nrow(malformed_levels$design$variables)), levels = named_levels, class = "factor")
  expect_error(nis_descriptive_table(malformed_levels, spec[1L, ], "exclude", 2,
    0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
    "Grouping factor levels")
  extra_attribute <- factored
  attr(extra_attribute$design$variables[["group `field"]], "label") <- "unexpected"
  expect_error(nis_descriptive_table(extra_attribute, spec[1L, ], "exclude", 2,
    0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
    "additional attributes")
  malformed_class <- factored
  class(malformed_class$design$variables[["group `field"]]) <- c("labelled", "factor")
  expect_error(nis_descriptive_table(malformed_class, spec[1L, ], "exclude", 2,
    0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
    "standard unordered factor")
  before_failure <- factored
  all_missing_outcome <- factored
  all_missing_outcome$design$variables$LOS[all_missing_outcome$design$variables[["group `field"]] == "Beta"] <- NA_real_
  expect_error(nis_descriptive_table(all_missing_outcome, spec[1L, ], "exclude", 2,
    0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
    "empty analysis")
  expect_identical(factored, before_failure)
  no_groups <- factored
  no_groups$design$variables[["group `field"]] <- factor(rep(NA_character_,
    nrow(no_groups$design$variables)), levels = c("Only", "Unused"))
  expect_error(nis_descriptive_table(no_groups, spec[1L, ], "exclude", 2,
    0.95, "wr_unadjusted", by = "group `field", group_missing = "exclude"),
    "no observed groups")
  for (format in c("csv", "html", "docx")) {
    destination <- tempfile(fileext = paste0(".", format))
    writeLines("keep existing", destination)
    expect_error(nis_export_table(result, destination, format,
      if (format == "csv") NULL else 3, if (format == "csv") "refuse" else NULL, TRUE),
      "Only a nis_disclosure_review")
    expect_identical(readLines(destination), "keep existing")
    unlink(destination)
    absent <- tempfile(fileext = paste0(".", format))
    expect_error(nis_export_table(result, absent, format,
      if (format == "csv") NULL else 3, if (format == "csv") "refuse" else NULL, FALSE),
      "Only a nis_disclosure_review")
    expect_false(file.exists(absent))
  }
})
