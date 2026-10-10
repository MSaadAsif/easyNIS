# Run offline with source(system.file("examples/pooled-model-workflow.R", package = "easyNIS")).
# Copy the returned report/CSV/HTML files together before ending the R session.
library(easyNIS)
(function() {
  fixture <- new.env(parent = baseenv())
  sys.source(system.file("examples/workflow-fixture.R", package = "easyNIS"), fixture)
  codes <- nis_code_set("A001", "ICD10CM", 2017:2022,
    "invented-1", "pooled-model-workflow.R invented declaration", "easyNIS example",
    match = "exact", normalize = FALSE)
  session <- nis_open()
  paths <- character()
  on.exit({ nis_close(session); unlink(paths) })
  annual <- lapply(seq_along(2017:2022), function(i) {
    year <- 2016L + i
    core <- fixture$workflow_fixture(year, multiplier = i, shift = i - 1)
    if (i > 1L) core$rare <- 0L
    path <- tempfile(fileext = ".parquet")
    paths <<- c(paths, path)
    DBI::dbWriteTable(session$connection, "invented_pool", core, overwrite = TRUE)
    DBI::dbExecute(session$connection, paste0("COPY invented_pool TO ",
      DBI::dbQuoteString(session$connection, path), " (FORMAT PARQUET)"))
    imported <- nis_import(session, path, year)
    stopifnot(nis_validate(imported)$structural_errors == 0)
    flagged <- nis_flag_codes(imported, "cohort", codes,
      "principal_diagnosis", "no_match", slots = 1)
    nis_survey_design(flagged, c("cohort", "LOS", "rare"), TRUE, "hospital_wr", "fail")
  })
  pooled <- nis_pool_design(annual, c("cohort", "LOS", "rare"), "average_annual_total")
  stopifnot(pooled$population$hospitals == 24L, pooled$population$strata == 12L,
    pooled$population$degrees_of_freedom == 12)
  domain <- nis_domain(pooled, "cohort", "fail")
  spec <- data.frame(id = c("stay", "total", "rare"), field = c("LOS", "LOS", "rare"),
    statistic = c("mean", "total", "total"),
    label = c("Invented pooled stay", "Invented average annual LOS", "Invented rare indicator"),
    unit = c("days", "weighted discharge-days per year", "weighted discharges per year"))
  table <- nis_descriptive_table(domain, spec, "exclude", 12, 0.95, "wr_unadjusted")
  model <- nis_model(domain, LOS ~ 1, "gaussian", "exclude", 12, 0.95, "wr_unadjusted")

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
    "Exact principal diagnosis match, slot 1 (I10_DX1); normalization FALSE; missing codes use no_match.",
    "Domain: cohort == TRUE after full-design pooling; unknown values fail.",
    "Design: hospital_wr; HOSP_NIS, NIS_STRATUM, DISCWT; singleton fail; no FPC; year-specific hospital/stratum keys.",
    "Pool intent: average_annual_total; native annual weights divided by 6; raw weights retained.",
    "Pooled mean is weighted across supplied discharges, not an arithmetic average of annual means.",
    "Outcome missingness: exclude per descriptive row and complete cases for the model.",
    "Variance: wr_unadjusted; interval df 12; confidence 0.95; two-sided Wald t intervals.",
    "Model: LOS ~ 1; Gaussian identity; coefficient/response scale days; no offset, exponentiation or causal interpretation.",
    "The internal model intercept and sandwich SE match independent hospital WR ratio arithmetic.",
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
