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
  scalar <- nis_estimate(domain, "LOS", "total", "fail", 2, 0.95, "wr_unadjusted")
  mean <- nis_estimate(domain, "LOS", "mean", "fail", Inf, 0.9, "wr_unadjusted")
  proportion <- nis_estimate(design, "domain", "proportion", "fail", 2, 0.95, "wr_unadjusted")
  stopifnot(abs(scalar$estimate - 44) < 1e-12,
    abs(scalar$se - sqrt(968)) < 1e-12,
    abs(scalar$lower - (44 - stats::qt(0.975, 2) * sqrt(968))) < 1e-12,
    abs(scalar$upper - (44 + stats::qt(0.975, 2) * sqrt(968))) < 1e-12,
    scalar$sample$included == 6L, scalar$sample$excluded_missing == 0L,
    abs(mean$estimate - 22 / 9) < 1e-12, abs(mean$se) < 1e-12,
    abs(proportion$estimate - 0.5) < 1e-12,
    abs(proportion$se - sqrt(162) / 36) < 1e-12,
    inherits(scalar$native, "svystat"), identical(scalar$provenance$analysis_ready, FALSE))
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
  cat("Invented year", year, "passed all three model links against independent intercept references.\n")
  cat("Invented year", year, "passed import, flags, selection, survey domains and scalar estimate references.\n")
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
cat("Installed workflow passed; year support remains experimental.\n")
