# Run offline with source(system.file("examples/pooled-model-workflow.R", package = "easyNIS")).
# Copy the returned report/CSV/HTML files together before ending the R session.
library(easyNIS)
(function() {
  # Explicit invented-example choices, restored on exit; not licensed-data policy.
  previous <- options(survey.lonely.psu = "fail", survey.adjust.domain.lonely = FALSE,
    contrasts = c("contr.treatment", "contr.poly"))
  on.exit(options(previous), add = TRUE)
  fixture <- new.env(parent = baseenv())
  sys.source(system.file("examples/workflow-fixture.R", package = "easyNIS"), fixture)
  codes <- nis_code_set("A001", "ICD10CM", 2017:2022,
    "invented-1", "pooled-model-workflow.R invented declaration", "easyNIS example",
    match = "exact", normalize = FALSE)
  session <- nis_open()
  paths <- character()
  on.exit({ nis_close(session); unlink(paths) }, add = TRUE)
  annual <- lapply(seq_along(2017:2022), function(i) {
    year <- 2016L + i
    core <- fixture$workflow_fixture(year, multiplier = i, shift = i - 1)
    hospital <- as.integer(core$HOSP_NIS)
    core$AGE <- 16 + seq_len(nrow(core)) %% 65
    cohort_rows <- core$I10_DX1 == "A001"
    core$AGE[cohort_rows] <- 18 + seq_len(sum(cohort_rows)) %% 60
    core$exposure <- hospital %% 2L == 1L
    core$event <- as.integer(seq_len(nrow(core)) %% 7L < hospital + 1L)
    core$event[7L] <- NA_integer_
    core$I10_DX1[c(2L, 4L)] <- c("invl", "incn")
    if (i > 1L) core$rare <- 0L
    path <- tempfile(fileext = ".parquet")
    paths <<- c(paths, path)
    DBI::dbWriteTable(session$connection, "invented_pool", core, overwrite = TRUE)
    DBI::dbExecute(session$connection, paste0("COPY invented_pool TO ",
      DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
    imported <- nis_import(session, path, year)
    stopifnot(nis_validate(imported)$structural_errors == 0)
    flagged <- nis_flag_codes(imported, "cohort", codes,
      "principal_diagnosis", "no_match", slots = 1, special_missing = "hcup_character")
    observed <- nis_collect(flagged, c("KEY_NIS", "I10_DX1", "cohort"), limit = 120)
    source_order <- match(observed$KEY_NIS, core$KEY_NIS)
    expected <- cohort_rows
    expected[c(2L, 4L)] <- NA
    stopifnot(identical(observed$I10_DX1, core$I10_DX1[source_order]),
      identical(observed$cohort, expected[source_order]),
      identical(flagged$flags$cohort$special_missing$values,
        c(invalid = "invl", inconsistent = "incn")))
    nis_survey_design(flagged, c("cohort", "LOS", "rare", "AGE", "exposure", "event"),
      TRUE, "hospital_wr", "fail")
  })
  pooled <- nis_pool_design(annual, c("cohort", "LOS", "rare", "AGE", "exposure", "event"),
    "average_annual_total")
  stopifnot(pooled$population$hospitals == 24L, pooled$population$strata == 12L,
    pooled$population$degrees_of_freedom == 12)
  analysis <- nis_factor(pooled, "exposure", "exposure_factor", c(FALSE, TRUE),
    c("Comparator", "Exposed"))
  domain <- nis_domain(analysis, ~ AGE >= 18 & cohort, "exclude")
  stopifnot(domain$domains[[1L]]$included == 360L,
    domain$domains[[1L]]$unknown == 12L, domain$domains[[1L]]$excluded_false == 348L)
  spec <- data.frame(id = c("stay", "total", "rare"), field = c("LOS", "LOS", "rare"),
    statistic = c("mean", "total", "total"),
    label = c("Invented pooled stay", "Invented average annual LOS", "Invented rare indicator"),
    unit = c("days", "weighted discharge-days per year", "weighted discharges per year"))
  table <- nis_descriptive_table(domain, spec, "exclude", 12, 0.95, "wr_unadjusted")
  model <- nis_model(domain, LOS ~ 1, "gaussian", "exclude", 12, 0.95, "wr_unadjusted")
  families <- c(LOS = "gaussian", event = "quasibinomial")
  batch <- nis_models(domain, families, ~ exposure_factor,
    "exclude", 12, 0.95, "wr_unadjusted")
  stopifnot(identical(batch$sample$raw_included, c(288, 354)),
    identical(batch$sample$raw_missing, c(72, 6)),
    identical(analysis$design$variables$exposure, pooled$design$variables$exposure),
    identical(domain$population, pooled$population))

  # Separate GLM coefficients and hospital-score WR covariance, not survey fits.
  population <- analysis$design$variables
  weights <- population$DISCWT / 6
  predicate <- population$cohort & population$AGE >= 18
  eligible <- !is.na(predicate) & predicate
  stopifnot(sum(is.na(predicate)) == 12L, sum(eligible) == 360L)
  hospital <- paste(population$YEAR, population$HOSP_NIS, sep = ":")
  strata <- paste(population$YEAR, population$NIS_STRATUM, sep = ":")
  for (field in names(families)) {
    keep <- eligible & !is.na(population[[field]])
    family <- if (families[[field]] == "gaussian") stats::gaussian() else stats::quasibinomial()
    reference <- stats::glm(stats::reformulate("exposure_factor", field),
      data = population[keep, ], family = family, weights = weights[keep] / base::mean(weights[keep]),
      control = stats::glm.control(epsilon = 1e-10, maxit = 50L))
    model_matrix <- stats::model.matrix(reference)
    mu <- stats::fitted(reference)
    derivative <- family$mu.eta(reference$linear.predictors)
    bread <- solve(crossprod(model_matrix,
      model_matrix * (weights[keep] * derivative^2 / family$variance(mu))))
    score <- matrix(0, nrow(population), ncol(model_matrix))
    score[keep, ] <- model_matrix * (weights[keep] * (population[[field]][keep] - mu) *
      derivative / family$variance(mu))
    totals <- rowsum(score, hospital)
    mapping <- strata[match(rownames(totals), hospital)]
    meat <- matrix(0, ncol(model_matrix), ncol(model_matrix))
    for (stratum in unique(mapping)) {
      values <- totals[mapping == stratum, , drop = FALSE]
      centered <- sweep(values, 2L, colMeans(values))
      meat <- meat + nrow(values) / (nrow(values) - 1L) * crossprod(centered)
    }
    covariance <- bread %*% meat %*% bread
    result <- batch$models[[field]]
    tolerance <- if (field == "LOS") 1e-10 else 1e-7
    stopifnot(max(abs(stats::coef(result$native) - stats::coef(reference))) < 1e-8,
      max(abs(stats::vcov(result$native) - covariance)) < tolerance,
      max(abs(result$coefficients$lower - (stats::coef(reference) -
        stats::qt(0.975, 12) * sqrt(diag(covariance))))) < tolerance,
      result$sample$included == sum(keep),
      abs(result$sample$weighted_denominator - sum(weights[keep])) < 1e-9,
      isTRUE(result$diagnostics$converged), !isTRUE(result$diagnostics$boundary),
      length(result$diagnostics$warnings) == 0L)
  }

  # Independent hospital WR arithmetic: base hospital weights W=(24,36,48,60)
  # and totals T=(72,144,240,360). Year i has i*W and i*(T+(i-1)*W).
  # Sum i^2=91, i^3=441, i^4=2275. See docs/WORKFLOW.md for residual differences.
  mean <- 172 / 21
  mean_se <- sqrt(144 * (2 * 2275 - 100 / 21 * 441 +
    (67^2 + 17^2) / 21^2 * 91)) / 3528
  total <- 4816
  total_se <- sqrt(106176)
  for (id in c("stay", "total")) {
    estimate <- if (id == "stay") mean else total
    se <- if (id == "stay") mean_se else total_se
    result <- table$results[[id]]
    stopifnot(abs(result$estimate - estimate) < 1e-9,
      abs(result$se - se) < 1e-9,
      abs(result$lower - (estimate - stats::qt(0.975, 12) * se)) < 1e-9,
      abs(result$upper - (estimate + stats::qt(0.975, 12) * se)) < 1e-9,
      result$sample$included == 288L, result$sample$excluded_missing == 72L)
  }
  stopifnot(nrow(model$coefficients) == 1L,
    model$coefficients$term == "(Intercept)",
    abs(model$coefficients$estimate - mean) < 1e-9,
    abs(model$coefficients$se - mean_se) < 1e-9,
    abs(model$coefficients$lower - (mean - stats::qt(0.975, 12) * mean_se)) < 1e-9,
    abs(model$coefficients$upper - (mean + stats::qt(0.975, 12) * mean_se)) < 1e-9,
    model$sample$included == 288L, model$sample$excluded_missing == 72L,
    isTRUE(model$diagnostics$converged))
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  stopifnot(identical(review$presentation$disclosure_status,
    c("shown", "shown", "suppressed_primary")), is.na(review$presentation$estimate[3L]))

  output <- tempfile("easyNIS-pooled-model-workflow-")
  dir.create(output)
  complete <- FALSE
  on.exit(if (!complete) unlink(output, recursive = TRUE), add = TRUE)
  csv <- nis_export_table(review, file.path(output, "table.csv"), "csv", NULL, "refuse", FALSE)
  html <- nis_export_table(review, file.path(output, "table.html"), "html", 4, NULL, FALSE)
  versions <- vapply(c("easyNIS", "DBI", "duckdb", "survey"),
    function(package) as.character(utils::packageVersion(package)), character(1))
  # Fixed whitelist. Model coefficients/accounting/designs remain internal;
  # model disclosure review and regression-table export are unsupported.
  report <- c("# Invented pooled/model workflow report", "",
    "Experimental; not analysis ready. No annual support or scientific approval is claimed.",
    "All records, code assignments and year labels are invented; no audited annual layouts or clinical cohorts.",
    "", "## Versions", "", paste("R", as.character(getRversion())), paste(names(versions), versions),
    "", "## Analysis declarations", "",
    "Included invented labels: 2017 through 2022; complete supplied populations before pooling and domain selection.",
    "Code set: A001 ICD10CM; valid labels 2017 through 2022; version invented-1; author easyNIS example.",
    "Code source: pooled-model-workflow.R invented declaration.",
    "Exact principal diagnosis match, slot 1 (I10_DX1); normalization FALSE; blank codes use no_match.",
    "Character quality policy: explicit hcup_character; lowercase invl/incn remain raw, distinct and unknown unless positive.",
    "Invented quality markers: two noncohort codes per year; 12 unknown cohort predicates excluded after pooling.",
    "Domain: AGE >= 18 & cohort after full-design pooling; unknown values exclude; all invented cohort members are adults.",
    "Design: hospital_wr; HOSP_NIS, NIS_STRATUM, DISCWT; singleton fail; no FPC; year-specific hospital/stratum keys.",
    "Pool intent: average_annual_total; native annual weights divided by 6; raw weights retained.",
    "Pooled mean is weighted across supplied discharges, not an arithmetic average of annual means.",
    "Outcome missingness: exclude per descriptive row and complete cases for the model.",
    "Variance: wr_unadjusted; interval df 12; confidence 0.95; two-sided Wald t intervals.",
    "Model: LOS ~ 1; Gaussian identity; coefficient/response scale days; no offset, exponentiation or causal interpretation.",
    "The internal model intercept and sandwich SE match independent hospital WR ratio arithmetic.",
    "Analysis factor: exposure_factor declares raw FALSE/TRUE as Comparator/Exposed; raw exposure is preserved and mapping is unverified.",
    "Internal outcome batch: LOS Gaussian identity and event quasibinomial logit; shared predictors exposure_factor; separate complete-case samples.",
    "Fixture-only options: lonely PSU fail, domain adjustment FALSE, treatment contrasts; caller options restored on exit.",
    "Independent GLM coefficients and hospital-score WR covariance verify the batch; inference is pointwise with no multiplicity correction.",
    "No clinical meaning, odds/risk interpretation, causal claim or annual validity is inferred from the invented exposure/event labels.",
    "Rows: pooled LOS mean; average annual LOS total; average annual rare indicator total.",
    "Disclosure: suppress raw counts 1 through 10; display zero; minimum 2 contributing hospitals; no declared margins.",
    "Bounded disclosure requires human review of undeclared relations, larger margin combinations and external publications.",
    "Only reviewed descriptive values are exported. Model disclosure review and regression-table export are unsupported.",
    "CSV uses exact numbers and refuses formula-leading text; HTML uses 4 significant digits for estimates, SEs and intervals.",
    "", "## Reviewed descriptive outputs", "",
    "[Exact CSV table](table.csv)", "[HTML table with disclosure notes](table.html)", "",
    "Raw records, suppressed values, model results, accounting, retained provenance/designs and local source paths are omitted.")
  report_path <- file.path(output, "report.md")
  writeLines(report, report_path, useBytes = TRUE)
  complete <- TRUE
  list(report = normalizePath(report_path), csv = csv, html = html)
})()
