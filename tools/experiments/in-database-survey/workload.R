source("tools/experiments/in-database-survey/taylor.R")

design_fields <- c("YEAR", "HOSP_NIS", "NIS_STRATUM", "DISCWT")
valid_design <- paste(sprintf("coalesce(isfinite(%1$s) AND %1$s > 0, false)",
  design_fields), collapse = " AND ")
adult <- "AGE >= 65 AND FEMALE = 1"
workloads <- list(
  mean = list(y = "LOS"), total = list(y = "DIED", total = TRUE),
  by = list(y = "LOS", group = "YEAR"),
  adult_mean = list(y = "LOS", domain = adult),
  adult_by = list(y = "LOS", domain = adult, group = "YEAR"),
  srvyr = list(y = "LOS", domain = adult, group = "YEAR"),
  glm = list(y = "DIED", family = "quasibinomial"),
  adult_glm = list(y = "DIED", domain = "AGE >= 65", family = "quasibinomial"),
  gaussian = list(y = "LOS", family = "gaussian"),
  poisson = list(y = "LOS", family = "poisson")
)
fixture_cases <- list(
  numeric_total = list(y = "LOS", total = TRUE),
  binary_mean = list(y = "DIED"),
  age_by_sex = list(y = "LOS", group = "FEMALE", domain = "AGE >= 65"),
  missing_mean = list(y = "LOS", na.rm = FALSE)
)

open_views <- function(con, paths) {
  quoted <- paste(DBI::dbQuoteString(con, paths), collapse = ", ")
  DBI::dbExecute(con, sprintf(paste(
    "CREATE VIEW raw_input AS SELECT YEAR, HOSP_NIS, NIS_STRATUM, DISCWT, filename,",
    "%s FROM read_parquet([%s], union_by_name = true, hive_partitioning = false,",
    "filename = true)"), paste(sprintf(
      "nullif(CAST(%1$s AS DOUBLE), 'NaN'::DOUBLE) AS %1$s",
      c("AGE", "FEMALE", "LOS", "DIED")), collapse = ", "), quoted))
  DBI::dbExecute(con, paste("CREATE VIEW valid AS SELECT * EXCLUDE (filename)",
    "FROM raw_input WHERE", valid_design))
}

sql_call <- function(query, call, years) {
  spec <- c(workloads, fixture_cases)[[call]]
  if (!is.null(spec$family)) {
    year_terms <- sprintf("factor(YEAR)%d", years[-1L])
    columns <- c("(Intercept)" = "1.0", AGE = "AGE", FEMALE = "FEMALE",
      stats::setNames(sprintf("CAST(YEAR = %d AS DOUBLE)", years[-1L]), year_terms))
    # Sex is constant in the age/sex domain. Use an age-only domain for this fit.
    return(taylor_glm(query, spec$y, columns, spec$family, spec$domain %||% "true"))
  }
  taylor_stat(query, spec$y, total = isTRUE(spec$total), domain = spec$domain %||% "true",
    group = spec$group, na.rm = spec$na.rm %||% TRUE)
}

reference_design <- function(data) {
  stopifnot(all(data$HOSP_NIS < 1e6), all(data$NIS_STRATUM < 1e6),
    all(data$YEAR == as.integer(data$YEAR)),
    all(data$HOSP_NIS == as.integer(data$HOSP_NIS)),
    all(data$NIS_STRATUM == as.integer(data$NIS_STRATUM)))
  data$psu <- (data$YEAR - 2018) * 1e6 + data$HOSP_NIS
  data$stratum <- (data$YEAR - 2018) * 1e6 + data$NIS_STRATUM
  survey::svydesign(ids = ~psu, strata = ~stratum, weights = ~DISCWT,
    nest = TRUE, data = data)
}

reference_call <- function(design, call) {
  spec <- c(workloads, fixture_cases)[[call]]
  if (!is.null(spec$domain)) {
    inside <- with(design$variables, AGE >= 65)
    if (identical(spec$domain, adult)) inside <- inside & design$variables$FEMALE == 1
    design <- subset(design, inside)
  }
  y <- stats::reformulate(spec$y)
  na.rm <- spec$na.rm %||% TRUE
  if (!is.null(spec$family)) {
    family <- get(spec$family, envir = asNamespace("stats"))()
    fit <- survey::svyglm(stats::reformulate(c("AGE", "FEMALE", "factor(YEAR)"), spec$y),
      design, family = family, rescale = FALSE,
      control = stats::glm.control(epsilon = 1e-10))
    stopifnot(fit$converged)
    return(list(estimate = stats::coef(fit), se = survey::SE(fit),
      vcov = stats::vcov(fit), df = fit$df.residual, iterations = fit$iter))
  }
  if (call == "srvyr") {
    fit <- design |>
      srvyr::as_survey() |>
      dplyr::group_by(YEAR) |>
      dplyr::summarise(LOS = srvyr::survey_mean(LOS, na.rm = TRUE))
    return(list(estimate = stats::setNames(fit$LOS, fit$YEAR),
      se = stats::setNames(fit$LOS_se, fit$YEAR)))
  }
  fun <- if (isTRUE(spec$total)) survey::svytotal else survey::svymean
  if (is.null(spec$group)) {
    fit <- fun(y, design, na.rm = na.rm)
    keys <- spec$y
  } else {
    fit <- survey::svyby(y, stats::reformulate(spec$group), design, fun, na.rm = na.rm)
    keys <- fit[[spec$group]]
  }
  list(estimate = stats::setNames(stats::coef(fit), keys),
    se = stats::setNames(as.numeric(survey::SE(fit)), keys))
}

differences <- function(actual, expected) {
  relative <- function(x, y) {
    if (!identical(dim(x), dim(y)) || !identical(dimnames(x), dimnames(y)) ||
        !identical(names(x), names(y)) || length(x) != length(y) ||
        any(is.na(x) != is.na(y))) return(Inf)
    max(abs(x - y) / pmax(abs(x), abs(y), .Machine$double.xmin), 0, na.rm = TRUE)
  }
  out <- c(estimate = relative(actual$estimate, expected$estimate),
    se = relative(actual$se, expected$se), vcov = 0, df = 0, iterations = 0)
  if (!is.null(expected$vcov)) {
    out["vcov"] <- relative(actual$vcov, expected$vcov)
    out["df"] <- abs(actual$df - expected$df)
    out["iterations"] <- abs(actual$iterations - expected$iterations)
  }
  out
}
