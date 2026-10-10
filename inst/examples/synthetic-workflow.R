# Run offline with source(system.file("examples/synthetic-workflow.R", package = "easyNIS")).
# The returned paths point to a new temporary directory. Copy its three files
# together to keep the report's relative links working.
library(easyNIS)
(function() {
  fixture <- new.env(parent = baseenv())
  sys.source(system.file("examples/workflow-fixture.R", package = "easyNIS"), fixture)
  core <- fixture$workflow_fixture(2022)
  codes <- nis_code_set("A001", "ICD10CM", 2022,
    "invented-1", "synthetic-workflow.R invented declaration", "easyNIS example",
    match = "exact", normalize = FALSE)

  session <- nis_open()
  parquet <- tempfile(fileext = ".parquet")
  on.exit({ nis_close(session); unlink(parquet) })
  DBI::dbWriteTable(session$connection, "invented_workflow", core)
  DBI::dbExecute(session$connection, paste0("COPY invented_workflow TO ",
    DBI::dbQuoteString(session$connection, parquet), " (FORMAT PARQUET)"))
  imported <- nis_import(session, parquet, 2022)
  stopifnot(nis_validate(imported)$structural_errors == 0)
  flagged <- nis_flag_codes(imported, "cohort", codes,
    "principal_diagnosis", "no_match", slots = 1)
  full <- nis_survey_design(flagged, c("cohort", "LOS", "rare"),
    TRUE, "hospital_wr", "fail")
  domain <- nis_domain(full, "cohort", "fail")
  spec <- data.frame(id = c("stay", "rare"), field = c("LOS", "rare"),
    statistic = c("mean", "total"), label = c("Invented stay", "Invented rare indicator"),
    unit = c("days", "weighted discharges"))
  table <- nis_descriptive_table(domain, spec, "exclude", 2, 0.95, "wr_unadjusted")

  # Independent hospital WR ratio reference. Observed hospital weighted totals
  # are 72,144,240,360 and observed weights are 24,36,48,60. Their sum ratio is 34/7.
  # Linearized residual totals are -312/7,-216/7,48/7,480/7. With two hospitals per stratum,
  # total variance is the sum of squared within-stratum differences.
  mean_result <- table$results$stay
  reference_mean <- 34 / 7
  reference_se <- sqrt(96^2 + 432^2) / (7 * 168)
  stopifnot(abs(mean_result$estimate - reference_mean) < 1e-12,
    abs(mean_result$se - reference_se) < 1e-12,
    abs(mean_result$lower - (reference_mean - stats::qt(0.975, 2) * reference_se)) < 1e-12,
    abs(mean_result$upper - (reference_mean + stats::qt(0.975, 2) * reference_se)) < 1e-12)
  review <- nis_disclosure_review(table, c(1, 10), "display", 2, list())
  stopifnot(identical(review$presentation$disclosure_status,
    c("shown", "suppressed_primary")),
    is.na(review$presentation$estimate[2L]))

  output <- tempfile("easyNIS-synthetic-workflow-")
  dir.create(output)
  complete <- FALSE
  on.exit(if (!complete) unlink(output, recursive = TRUE), add = TRUE)
  csv <- nis_export_table(review, file.path(output, "table.csv"), "csv", NULL, "refuse", FALSE)
  html <- nis_export_table(review, file.path(output, "table.html"), "html", 4, NULL, FALSE)
  # Deliberate whitelist. Never print sessionInfo(), full provenance, the table's
  # retained results, survey objects, source receipts or local paths here.
  versions <- vapply(c("easyNIS", "DBI", "duckdb", "survey"),
    function(package) as.character(utils::packageVersion(package)), character(1))
  report <- c(
    "# Invented easyNIS workflow report", "",
    "Experimental; not analysis ready. No annual support or scientific approval is claimed.",
    "All records and code assignments are invented. These are not clinical cohorts or audited annual layouts.",
    "", "## Versions", "", paste("R", as.character(getRversion())),
    paste(names(versions), versions),
    "", "## Analysis declarations", "",
    "Fixture year label: 2022. Input: locally generated parquet, complete invented population.",
    paste("Code set:", paste(codes$codes, collapse = ", "), codes$system,
      "valid year 2022; version", codes$version),
    paste("Code source:", codes$source, "Author:", codes$author),
    "Exact principal diagnosis match, slot 1 (I10_DX1); normalization FALSE; unmatched/missing codes use no_match.",
    "Domain: cohort == TRUE, selected after full-population construction; unknown domain values fail.",
    "Design: hospital_wr; hospital HOSP_NIS, stratum NIS_STRATUM, weight DISCWT; singleton fail.",
    "Single-year estimand; native weights unscaled; no finite-population correction.",
    "Outcome missingness: exclude separately per row; observed outcomes define each denominator.",
    "Variance: wr_unadjusted; interval df 2; confidence 0.95; two-sided Wald t intervals.",
    "Rows: LOS mean in days; rare indicator total in weighted discharges.",
    "Disclosure: suppress raw counts 1 through 10; display zero; minimum 2 contributing hospitals; no declared margins.",
    "Disclosure procedure is bounded; undeclared relations and external publications need human review.",
    "CSV uses exact numbers and refuses formula-leading text; HTML uses 4 significant digits for estimates, SEs and intervals.",
    "", "## Reviewed outputs", "",
    "[Exact CSV table](table.csv)", "[HTML table with disclosure notes](table.html)",
    "", "The stay mean, SE and t interval match independent hospital-level WR arithmetic in the executable source.",
    "The report includes only the listed declarations and package versions. Raw data, suppressed values, audit counts and local source paths are omitted.")
  report_path <- file.path(output, "report.md")
  writeLines(report, report_path, useBytes = TRUE)
  complete <- TRUE
  list(report = normalizePath(report_path), csv = csv, html = html)
})()
