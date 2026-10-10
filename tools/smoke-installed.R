args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !dir.exists(args)) stop("Supply the isolated installed-package library.")
.libPaths(c(normalizePath(args), .libPaths()))
library(easyNIS)
if (normalizePath(find.package("easyNIS")) != normalizePath(file.path(args, "easyNIS"))) {
  stop("The workflow must use the newly installed source package.")
}
exercise_year <- function(year) {
  fixture <- nis_synthetic_data(year)
  core <- fixture$core
  core$I10_DX1 <- rep(c("A001", "B002"), length.out = nrow(core))
  core$domain <- core$HOSP_NIS %in% c("0001", "0003")
  core$exposure <- rep(c(1, 2, 3), length.out = nrow(core))
  core$contrast_x <- rep(c(-2, -1, 1), 4L) + rep(c(-0.4, 0.2, 0.6, -0.3), each = 3L)
  core$support_group <- ifelse(core$HOSP_NIS %in% c("0001", "0003"), "A", "B")
  session <- nis_open()
  path <- tempfile(fileext = ".parquet")
  on.exit({ nis_close(session); unlink(path) }, add = TRUE)
  DBI::dbWriteTable(session$connection, "invented", core)
  DBI::dbExecute(session$connection, paste0("COPY invented TO ",
    DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
  data <- nis_import(session, path, year)
  report <- nis_validate(data)
  stopifnot(!report$structural_errors, identical(report$analysis_ready, FALSE))
  codes <- nis_code_set("A001", "ICD10CM", year, "invented-smoke-1", "invented fixture", "verification")
  flagged <- nis_flag_codes(data, "invented_flag", codes, "principal_diagnosis", "no_match")
  rows <- nis_collect(flagged, c("KEY_NIS", "invented_flag"))
  expected <- core$I10_DX1[match(rows$KEY_NIS, core$KEY_NIS)] == "A001"
  stopifnot(nrow(rows) == nrow(core), identical(rows$invented_flag, expected))
  selected <- nis_select(flagged, c("KEY_NIS", "invented_flag"))
  selected_rows <- nis_collect(selected, c("KEY_NIS", "invented_flag"))
  stopifnot(nrow(selected_rows) == nrow(core),
            identical(selected_rows$invented_flag,
                      core$I10_DX1[match(selected_rows$KEY_NIS, core$KEY_NIS)] == "A001"))
  availability <- nis_validate(selected, c("invented_flag", "DISCWT", "UNDECLARED_FIELD"))$fields
  stopifnot(identical(availability$state, c("present", "user_omitted", "unverified_absent")),
            identical(availability$origin, c("derived", "imported", "unverified")),
            identical(availability$record_nulls, c(0, NA_real_, NA_real_)))
  source_dropped <- nis_select(data, c("KEY_NIS", "I10_DX1"))
  collision <- tryCatch(nis_flag_codes(source_dropped, "discwt", codes,
    "principal_diagnosis", "no_match"), error = identity)
  stopifnot(inherits(collision, "error"), grepl("conflicts", conditionMessage(collision)))
  design <- nis_survey_design(data, c("LOS", "domain", "exposure", "contrast_x", "support_group"), full_population = TRUE,
    method = "hospital_wr", singleton = "fail")
  domain <- nis_domain(design, "domain", "fail")
  total <- survey::svytotal(~LOS, domain$design)
  stopifnot(design$population$discharges == nrow(core),
    domain$population$hospitals == 4L, domain$domains[[1L]]$included == 6L,
    abs(unname(stats::coef(total)) - 44) < 1e-12,
    abs(unname(stats::vcov(total)) - (22^2 + 22^2)) < 1e-12,
    identical(design$provenance$analysis_ready, FALSE))
  scalar <- nis_estimate(domain, "LOS", "total", "fail", 2, 0.95, "wr_unadjusted")
  mean <- nis_estimate(domain, "LOS", "mean", "fail", Inf, 0.9, "wr_unadjusted")
  proportion <- nis_estimate(design, "domain", "proportion", "fail", 2, 0.95, "wr_unadjusted")
  table_spec <- data.frame(id = c("los", "share", "los_total"),
    field = c("LOS", "domain", "LOS"),
    statistic = c("mean", "proportion", "total"),
    label = c("Length of stay", "Domain share", "Weighted stay total"),
    unit = c("days", "proportion", "weighted days"))
  table <- nis_descriptive_table(design, table_spec, "exclude", 2, 0.95,
    "wr_unadjusted")
  independent <- function(field, statistic) {
    y <- as.double(core[[field]])
    keep <- !is.na(y)
    denominator <- sum(core$DISCWT[keep])
    estimate <- sum(core$DISCWT[keep] * y[keep])
    if (statistic != "total") estimate <- estimate / denominator
    contribution <- numeric(nrow(core))
    contribution[keep] <- core$DISCWT[keep] * if (statistic == "total") y[keep] else
      (y[keep] - estimate) / denominator
    hospitals <- tapply(contribution, core$HOSP_NIS, sum)
    strata <- core$NIS_STRATUM[match(names(hospitals), core$HOSP_NIS)]
    variance <- sum(vapply(split(hospitals, strata), function(x) {
      length(x) / (length(x) - 1) * sum((x - mean(x))^2)
    }, numeric(1)))
    c(estimate = estimate, se = sqrt(variance))
  }
  expected_table <- rbind(independent("LOS", "mean"),
    independent("domain", "proportion"), independent("LOS", "total"))
  stopifnot(abs(scalar$estimate - 44) < 1e-12,
    abs(scalar$se - sqrt(968)) < 1e-12,
    abs(scalar$lower - (44 - stats::qt(0.975, 2) * sqrt(968))) < 1e-12,
    abs(scalar$upper - (44 + stats::qt(0.975, 2) * sqrt(968))) < 1e-12,
    scalar$sample$included == 6L, scalar$sample$excluded_missing == 0L,
    abs(mean$estimate - 22 / 9) < 1e-12, abs(mean$se) < 1e-12,
    abs(proportion$estimate - 0.5) < 1e-12,
    abs(proportion$se - sqrt(162) / 36) < 1e-12,
    inherits(scalar$native, "svystat"), identical(scalar$provenance$analysis_ready, FALSE),
    inherits(table, "nis_descriptive_table"),
    identical(table$data$id, table_spec$id),
    max(abs(table$data$weighted_estimate - expected_table[, "estimate"])) < 1e-12,
    max(abs(table$data$se - expected_table[, "se"])) < 1e-12,
    identical(table$data$analysis_hospitals, c(4, 4, 4)),
    identical(table$data$raw_missing, c(0, 0, 0)),
    identical(table$results$los$native,
      nis_estimate(design, "LOS", "mean", "exclude", 2, 0.95, "wr_unadjusted")$native),
    identical(table$provenance$analysis_ready, FALSE))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  exposed <- function(rows) {
    count <- sum(rows)
    count >= 1 && count <= 10 || count > 0 && length(unique(core$HOSP_NIS[rows])) < 2
  }
  los_exposed <- exposed(core$LOS != 0) || exposed(rep(TRUE, nrow(core)))
  expected_review <- ifelse(c(los_exposed, exposed(core$domain) || exposed(!core$domain),
    los_exposed), "suppressed_primary", "shown")
  shown <- expected_review == "shown"
  stopifnot(inherits(review, "nis_disclosure_review"),
    identical(review$presentation$disclosure_status, expected_review),
    identical(review$presentation$estimate[shown], table$data$weighted_estimate[shown]),
    all(is.na(review$presentation$estimate[!shown])),
    all(is.na(review$presentation$unweighted_n[!shown])),
    !any(c("raw_missing", "raw_supplied", "analysis_hospitals", "weighted_denominator") %in%
      names(review$presentation)),
    identical(review$provenance$analysis_ready, FALSE))
  for (family in c("gaussian", "quasibinomial", "quasipoisson")) {
    field <- if (family == "quasibinomial") "domain" else "LOS"
    outcome <- as.double(core[[field]])
    keep <- !is.na(outcome)
    denominator <- sum(core$DISCWT[keep])
    mean <- sum(core$DISCWT[keep] * outcome[keep]) / denominator
    score <- numeric(nrow(core))
    score[keep] <- core$DISCWT[keep] * (outcome[keep] - mean) / denominator
    hospitals <- tapply(score, core$HOSP_NIS, sum)
    strata <- core$NIS_STRATUM[match(names(hospitals), core$HOSP_NIS)]
    variance <- sum(vapply(split(hospitals, strata), function(x) {
      length(x) / (length(x) - 1) * sum((x - base::mean(x))^2)
    }, numeric(1)))
    coefficient <- switch(family, gaussian = mean, quasibinomial = stats::qlogis(mean),
      quasipoisson = log(mean))
    derivative <- switch(family, gaussian = 1, quasibinomial = 1 / (mean * (1 - mean)),
      quasipoisson = 1 / mean)
    fit <- nis_model(design, stats::reformulate("1", field), family, "exclude",
      2, 0.95, "wr_unadjusted")
    se <- sqrt(variance) * derivative
    stopifnot(abs(fit$coefficients$estimate - coefficient) < 1e-8,
      abs(fit$coefficients$se - se) < 1e-7,
      abs(fit$coefficients$lower - (coefficient - stats::qt(0.975, 2) * se)) < 1e-7,
      fit$sample$included == sum(keep), fit$sample$excluded_missing == sum(!keep),
      inherits(fit$native, "svyglm"), identical(fit$provenance$analysis_ready, FALSE))
  }
  design$design$variables$support_group <- factor(core$support_group,
    levels = c("A", "B", "EMPTY"))
  support_fit <- nis_model(design, LOS ~ support_group, "gaussian", "exclude",
    2, 0.95, "wr_unadjusted")
  support <- support_fit$diagnostics$factor_support$support_group
  stopifnot(identical(support$level, c("A", "B", "EMPTY")),
    identical(as.numeric(support[1L, -1L]), c(6, 6, 18, 2)),
    identical(as.numeric(support[2L, -1L]), c(6, 6, 18, 2)),
    identical(as.numeric(support[3L, -1L]), c(0, 0, 0, 0)))
  cat("Invented year", year, "passed installed factor support counts.\n")
  cat("Invented year", year, "passed all three model links against independent intercept references.\n")
  for (kind in c("transformed_gaussian", "offset_poisson")) {
    keep <- !is.na(core$LOS)
    y <- if (kind == "transformed_gaussian") log1p(core$LOS) else core$LOS
    w <- core$DISCWT
    if (kind == "transformed_gaussian") {
      coefficient <- sum(w[keep] * y[keep]) / sum(w[keep])
      score <- w[keep] * (y[keep] - coefficient) / sum(w[keep])
      fit <- nis_model(design, log1p(LOS) ~ 1, "gaussian", "exclude", 2, 0.95, "wr_unadjusted")
      stopifnot(identical(fit$provenance$modeled_scale, "transformed_outcome"),
        identical(fit$provenance$response_expression, "log1p(LOS)"))
    } else {
      rate <- sum(w[keep] * y[keep]) / sum(w[keep] * core$exposure[keep])
      coefficient <- log(rate)
      score <- w[keep] * (y[keep] - rate * core$exposure[keep]) / sum(w[keep] * y[keep])
      fit <- nis_model(design, LOS ~ offset(log(exposure)), "quasipoisson", "exclude", 2, 0.95, "wr_unadjusted")
      stopifnot(identical(fit$provenance$offset$field, "exposure"),
        identical(fit$native$offset, log(core$exposure[keep])))
    }
    contribution <- numeric(nrow(core))
    contribution[keep] <- score
    hospitals <- tapply(contribution, core$HOSP_NIS, sum)
    strata <- core$NIS_STRATUM[match(names(hospitals), core$HOSP_NIS)]
    variance <- sum(vapply(split(hospitals, strata), function(x) {
      length(x) / (length(x) - 1) * sum((x - base::mean(x))^2)
    }, numeric(1)))
    stopifnot(abs(fit$coefficients$estimate - coefficient) < 1e-8,
      abs(fit$coefficients$se - sqrt(variance)) < 1e-7,
      fit$sample$included == sum(keep),
      identical(fit$design$variables$LOS, core$LOS[keep]))
  }
  cat("Invented year", year, "passed transformed-response and exposure-offset model references.\n")
  x <- cbind("(Intercept)" = 1, contrast_x = core$contrast_x)
  w <- core$DISCWT
  bread <- solve(crossprod(x, x * w))
  coefficients <- drop(bread %*% crossprod(x, w * core$LOS))
  score <- x * (w * (core$LOS - drop(x %*% coefficients)))
  hospitals <- rowsum(score, core$HOSP_NIS)
  mapping <- core$NIS_STRATUM[match(rownames(hospitals), core$HOSP_NIS)]
  meat <- matrix(0, 2L, 2L)
  for (stratum in unique(mapping)) {
    values <- hospitals[mapping == stratum, , drop = FALSE]
    centered <- sweep(values, 2L, colMeans(values))
    meat <- meat + nrow(values) / (nrow(values) - 1L) * crossprod(centered)
  }
  covariance <- bread %*% meat %*% bread
  fit <- nis_model(design, LOS ~ contrast_x, "gaussian", "fail", 2, 0.95, "wr_unadjusted")
  contrast <- nis_model_contrast(fit, c(contrast_x = 2), "mean_difference")
  expected <- 2 * coefficients[2L]
  se <- 2 * sqrt(covariance[2L, 2L])
  stopifnot(abs(contrast$estimate - expected) < 1e-10,
    abs(contrast$link_se - se) < 1e-10,
    abs(contrast$effect_se - se) < 1e-10,
    abs(contrast$lower - (expected - stats::qt(0.975, 2) * se)) < 1e-10,
    abs(contrast$upper - (expected + stats::qt(0.975, 2) * se)) < 1e-10,
    abs(contrast$p_value - 2 * stats::pt(abs(expected / se), 2, lower.tail = FALSE)) < 1e-10,
    identical(contrast$model, fit), contrast$contrast[["(Intercept)"]] == 0,
    identical(contrast$provenance$analysis_ready, FALSE))
  cat("Invented year", year, "passed installed model contrast against independent slope/sandwich reference.\n")
  regression_spec <- data.frame(id = c("slope", "constant"),
    term = c("contrast_x", "(Intercept)"), label = c("Caller slope", "Caller constant"),
    unit = c("link", "link"))
  regression_table <- nis_regression_table(fit, regression_spec, "link")
  expected_coefficient <- stats::coef(fit$native)
  stopifnot(inherits(regression_table, "nis_regression_table"),
    identical(regression_table$data$id, regression_spec$id),
    max(abs(regression_table$data$estimate - coefficients[match(regression_spec$term, names(coefficients))])) < 1e-10,
    max(abs(regression_table$data$se - sqrt(diag(covariance))[match(regression_spec$term, names(coefficients))])) < 1e-10,
    identical(regression_table$data$estimate, unname(expected_coefficient[regression_spec$term])),
    identical(regression_table$data$se, fit$coefficients$se[match(regression_spec$term, fit$coefficients$term)]),
    identical(regression_table$data$analysis_hospitals, c(4, 4)),
    identical(regression_table$data$raw_supplied, c(12, 12)),
    identical(regression_table$data$disclosure_status, c("unreviewed", "unreviewed")),
    identical(regression_table$model, fit),
    identical(regression_table$provenance$analysis_ready, FALSE))
  cat("Invented year", year, "passed installed regression table coefficient and sample preservation.\n")
  cat("Invented year", year, "passed import, flags, selection, survey domains and scalar estimate references.\n")
  cat("Invented year", year, "passed installed descriptive table independent references.\n")
  design
}
designs <- lapply(2017:2022, exercise_year)
combined <- nis_pool_design(designs, c("LOS", "domain", "support_group"), "combined_total")
average <- nis_pool_design(designs, c("LOS", "domain", "support_group"), "average_annual_total")
combined_domain <- nis_domain(combined, "domain", "fail")
average_domain <- nis_domain(average, "domain", "fail")
pooled_support_fit <- nis_model(average, LOS ~ support_group, "gaussian", "exclude",
  12, 0.95, "wr_unadjusted")
pooled_table <- nis_regression_table(pooled_support_fit,
  data.frame(id = "group", term = "support_groupB", label = "Declared group", unit = "link"), "link")
stopifnot(identical(pooled_table$data$analysis_hospitals, 24),
  identical(pooled_table$data$raw_supplied, 72),
  identical(pooled_table$data$analysis_hospitals,
    as.double(length(unique(pooled_support_fit$design$cluster[[1L]])))))
pooled_support <- pooled_support_fit$diagnostics$factor_support$support_group
stopifnot(identical(pooled_support$level, c("A", "B", "EMPTY")),
  identical(as.numeric(pooled_support[1L, -1L]), c(36, 36, 18, 12)),
  identical(as.numeric(pooled_support[2L, -1L]), c(36, 36, 18, 12)),
  identical(as.numeric(pooled_support[3L, -1L]), c(0, 0, 0, 0)))
cat("Installed pooled factor support passed average-weight and reused-hospital counts.\n")
combined_total <- survey::svytotal(~LOS, combined_domain$design)
average_total <- survey::svytotal(~LOS, average_domain$design)
stopifnot(combined$population$discharges == 72L, combined$population$hospitals == 24L,
  combined$population$strata == 12L, combined$population$degrees_of_freedom == 12,
  abs(unname(stats::coef(combined_total)) - 264) < 1e-12,
  abs(unname(stats::vcov(combined_total)) - 5808) < 1e-12,
  abs(unname(stats::coef(average_total)) - 44) < 1e-12,
  abs(unname(stats::vcov(average_total)) - 5808 / 36) < 1e-12)
cat("Installed six-year pool passed exact year-key separation and explicit combined/average references.\n")
combined_estimate <- nis_estimate(combined_domain, "LOS", "total", "fail",
  12, 0.95, "wr_unadjusted")
average_estimate <- nis_estimate(average_domain, "LOS", "total", "fail",
  12, 0.95, "wr_unadjusted")
pooled_proportion <- nis_estimate(combined, "domain", "proportion", "fail",
  Inf, 0.9, "wr_unadjusted")
stopifnot(abs(combined_estimate$estimate - 264) < 1e-12,
  abs(combined_estimate$se - sqrt(5808)) < 1e-12,
  identical(combined_estimate$estimand, "combined_total"),
  abs(average_estimate$estimate - 44) < 1e-12,
  abs(average_estimate$se - sqrt(5808) / 6) < 1e-12,
  identical(average_estimate$estimand, "average_annual_total"),
  abs(pooled_proportion$estimate - 0.5) < 1e-12,
  abs(pooled_proportion$se - sqrt(972) / 216) < 1e-12,
  identical(pooled_proportion$estimand, "weighted_pooled_proportion"),
  abs(pooled_proportion$upper - (0.5 + stats::qnorm(0.95) * sqrt(972) / 216)) < 1e-12)
cat("Installed six-year scalar totals, SEs, intervals and weighted pooled proportion passed independent values.\n")
stopifnot(nrow(nis_supported_years(supported_only = TRUE)) == 0L)
subtotal_review <- source(system.file("examples/disclosure-subtotals.R", package = "easyNIS"),
  local = new.env())$value
subtotal_status <- stats::setNames(subtotal_review$presentation$disclosure_status,
  subtotal_review$presentation$id)
subtotal_shown <- subtotal_status == "shown"
stopifnot(identical(unname(subtotal_status[c("a", "b")]), rep("suppressed_primary", 2)),
  any(subtotal_status[c("all", "s", "e")] != "shown"),
  identical(unname(subtotal_status[["s"]]), "suppressed_complementary"),
  identical(subtotal_review$presentation$estimate[subtotal_shown],
    subtotal_review$table$data$weighted_estimate[subtotal_shown]),
  all(is.na(subtotal_review$presentation$estimate[!subtotal_shown])),
  all(is.na(subtotal_review$presentation$unweighted_n[!subtotal_shown])))
cat("Installed declared subtotals passed the seven-discharge hidden-sum regression.\n")
export_dir <- tempfile("easyNIS-export-smoke-")
dir.create(export_dir)
export_csv <- nis_export_table(subtotal_review, file.path(export_dir, "subtotals.csv"), "csv",
  NULL, "refuse", FALSE)
exported <- utils::read.csv(export_csv, stringsAsFactors = FALSE)
stopifnot(identical(names(exported), names(subtotal_review$presentation)),
  identical(exported$disclosure_status, subtotal_review$presentation$disclosure_status),
  identical(as.double(exported$estimate), as.double(subtotal_review$presentation$estimate)),
  identical(as.double(exported$unweighted_n), as.double(subtotal_review$presentation$unweighted_n)),
  all(is.na(exported$estimate[!subtotal_shown])))
export_html <- nis_export_table(subtotal_review, file.path(export_dir, "subtotals.html"), "html",
  4, NULL, FALSE)
html_text <- paste(readLines(export_html, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("Suppressed (complementary)", html_text, fixed = TRUE),
  grepl("not analysis ready", html_text, fixed = TRUE),
  inherits(tryCatch(nis_export_table(subtotal_review$table, file.path(export_dir, "raw.csv"),
    "csv", NULL, "refuse", FALSE), error = identity), "error"),
  !file.exists(file.path(export_dir, "raw.csv")))
formula_table <- nis_descriptive_table(designs[[length(designs)]],
  data.frame(id = "@los", field = "LOS", statistic = "mean",
    label = "=HYPERLINK(\"https://example.invalid\")", unit = "days"),
  "exclude", 2, 0.95, "wr_unadjusted")
formula_review <- nis_disclosure_review(formula_table, c(1, 10), "display", 2, list())
formula_csv <- file.path(export_dir, "formula.csv")
formula_refused <- tryCatch(nis_export_table(formula_review, formula_csv, "csv", NULL,
  "refuse", FALSE), error = conditionMessage)
stopifnot(grepl("id in row '@los', label in row '@los'", formula_refused, fixed = TRUE),
  !file.exists(formula_csv))
nis_export_table(formula_review, formula_csv, "csv", NULL, "prefix", FALSE)
formula_back <- utils::read.csv(formula_csv, stringsAsFactors = FALSE)
stopifnot(identical(formula_back$id, "'@los"),
  identical(formula_back$label, paste0("'", formula_review$presentation$label)))
export_docx <- nis_export_table(subtotal_review, file.path(export_dir, "subtotals.docx"),
  "docx", 4, NULL, FALSE)
docx_summary <- officer::docx_summary(officer::read_docx(export_docx))
docx_cells <- docx_summary[docx_summary$content_type == "table cell", ]
docx_cells <- docx_cells[order(docx_cells$row_id, docx_cells$cell_id), ]
docx_rows <- unname(split(docx_cells$text, docx_cells$row_id))[-1L]
html_rows <- regmatches(html_text, gregexpr("<tr>.*?</tr>", html_text))[[1L]][-1L]
html_rows <- lapply(html_rows, function(row) {
  gsub("&amp;", "&", gsub("</?td>", "", regmatches(row, gregexpr("<td>.*?</td>", row))[[1L]]),
    fixed = TRUE)
})
stopifnot(length(docx_rows) == nrow(subtotal_review$presentation),
  identical(docx_rows, html_rows),
  identical(vapply(docx_rows[!subtotal_shown], `[[`, character(1), 5L),
    rep("Suppressed", sum(!subtotal_shown))),
  any(grepl("not analysis ready", docx_summary$text, fixed = TRUE)))
unlink(export_dir, recursive = TRUE)
cat("Installed CSV, HTML and Word exports preserved shown values and suppression and handled formula text.\n")
workflow <- source(system.file("examples/synthetic-workflow.R", package = "easyNIS"),
  local = new.env())$value
stopifnot(identical(names(workflow), c("report", "csv", "html")),
  all(file.exists(unlist(workflow))))
workflow_csv <- utils::read.csv(workflow$csv, stringsAsFactors = FALSE)
workflow_report <- readLines(workflow$report, encoding = "UTF-8")
workflow_html <- paste(readLines(workflow$html, encoding = "UTF-8"), collapse = "\n")
reference_mean <- (72 + 144 + 240 + 360) / (24 + 36 + 48 + 60)
reference_se <- sqrt((96 / 7)^2 + (432 / 7)^2) / 168
stopifnot(identical(workflow_csv$disclosure_status, c("shown", "suppressed_primary")),
  abs(workflow_csv$estimate[1L] - reference_mean) < 1e-12,
  abs(workflow_csv$se[1L] - reference_se) < 1e-12,
  abs(workflow_csv$lower[1L] - (reference_mean - stats::qt(0.975, 2) * reference_se)) < 1e-12,
  abs(workflow_csv$upper[1L] - (reference_mean + stats::qt(0.975, 2) * reference_se)) < 1e-12,
  workflow_csv$unweighted_n[1L] == 48,
  all(is.na(workflow_csv[2L, c("estimate", "se", "lower", "upper", "unweighted_n")])),
  !any(c("raw_supplied", "raw_missing", "hospitals", "weighted_denominator") %in% names(workflow_csv)),
  grepl("Suppressed (primary)", workflow_html, fixed = TRUE),
  all(c("[Exact CSV table](table.csv)", "[HTML table with disclosure notes](table.html)") %in% workflow_report),
  any(grepl("wr_unadjusted; interval df 2; confidence 0.95", workflow_report, fixed = TRUE)),
  any(grepl("Code set: A001 ICD10CM", workflow_report, fixed = TRUE)),
  !any(grepl("[A-Za-z]:[/\\\\]|/tmp/|Rtmp|KEY_NIS|source_receipt|900719925474", workflow_report)),
  !any(vapply(unlist(workflow), function(path) any(grepl(path, workflow_report, fixed = TRUE)), logical(1))))
workflow_repeat <- source(system.file("examples/synthetic-workflow.R", package = "easyNIS"),
  local = new.env())$value
stopifnot(!identical(workflow, workflow_repeat),
  identical(readLines(workflow_repeat$report), workflow_report),
  identical(readBin(workflow_repeat$csv, "raw", file.info(workflow_repeat$csv)$size),
    readBin(workflow$csv, "raw", file.info(workflow$csv)$size)),
  identical(readLines(workflow_repeat$html), readLines(workflow$html)))
unlink(c(dirname(workflow$report), dirname(workflow_repeat$report)), recursive = TRUE)
cat("Installed offline quickstart passed independent WR inference, suppression, sanitized report and repeatability.\n")
vignette <- utils::vignette("synthetic-workflow", package = "easyNIS")
stopifnot(!is.null(vignette))
vignette_path <- system.file("doc/synthetic-workflow.html", package = "easyNIS")
stopifnot(nzchar(vignette_path), file.exists(vignette_path))
vignette_html <- paste(readLines(vignette_path, encoding = "UTF-8"), collapse = "\n")
stopifnot(grepl("Invented reviewed results", vignette_html, fixed = TRUE),
  grepl("suppressed_primary", vignette_html, fixed = TRUE),
  grepl("34/7", vignette_html, fixed = TRUE),
  !grepl("[A-Za-z]:[/\\\\]|/tmp/|Rtmp|source_receipt", vignette_html))
vignette_document <- xml2::read_html(vignette_path)
hidden_row <- xml2::xml_find_all(vignette_document,
  "//table//tr[td[contains(., 'suppressed_primary')]]")
stopifnot(length(hidden_row) == 1L)
headers <- trimws(xml2::xml_text(xml2::xml_find_all(vignette_document, "//table//th")))
hidden_cells <- trimws(xml2::xml_text(xml2::xml_find_all(hidden_row, "td")))
stopifnot(all(hidden_cells[match(c("estimate", "se", "lower", "upper", "unweighted_n"),
  headers)] == ""))

cat("Installed workflow passed; year support remains experimental.\n")
