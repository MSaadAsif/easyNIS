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
  design <- nis_survey_design(data, c("LOS", "domain"), full_population = TRUE,
    method = "hospital_wr", singleton = "fail")
  domain <- nis_domain(design, "domain", "fail")
  total <- survey::svytotal(~LOS, domain$design)
  stopifnot(design$population$discharges == nrow(core),
    domain$population$hospitals == 4L, domain$domains[[1L]]$included == 6L,
    abs(unname(stats::coef(total)) - 44) < 1e-12,
    abs(unname(stats::vcov(total)) - (22^2 + 22^2)) < 1e-12,
    identical(design$provenance$analysis_ready, FALSE))
  cat("Invented year", year, "passed import, flags, selection, survey domains and independent comparisons.\n")
  design
}
designs <- lapply(2017:2022, exercise_year)
combined <- nis_pool_design(designs, c("LOS", "domain"), "combined_total")
average <- nis_pool_design(designs, c("LOS", "domain"), "average_annual_total")
combined_domain <- nis_domain(combined, "domain", "fail")
average_domain <- nis_domain(average, "domain", "fail")
combined_total <- survey::svytotal(~LOS, combined_domain$design)
average_total <- survey::svytotal(~LOS, average_domain$design)
stopifnot(combined$population$discharges == 72L, combined$population$hospitals == 24L,
  combined$population$strata == 12L, combined$population$degrees_of_freedom == 12,
  abs(unname(stats::coef(combined_total)) - 264) < 1e-12,
  abs(unname(stats::vcov(combined_total)) - 5808) < 1e-12,
  abs(unname(stats::coef(average_total)) - 44) < 1e-12,
  abs(unname(stats::vcov(average_total)) - 5808 / 36) < 1e-12)
cat("Installed six-year pool passed exact year-key separation and explicit combined/average references.\n")
stopifnot(nrow(nis_supported_years(supported_only = TRUE)) == 0L)
cat("Installed workflow passed; year support remains experimental.\n")
