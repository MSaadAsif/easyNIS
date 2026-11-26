reviewer_cases <- function(con, d, years) {
  d$shifted_y <- 1e12 + d$LOS
  d$dollars <- 50000 + 4000L * d$AGE + 100 * d$LOS
  d$guarded <- ifelse(d$YEAR == years[1L], Inf, d$AGE)
  d$inflated <- 100 * d$DISCWT
  d$reweighted <- d$DISCWT * (1 + d$FEMALE / 4) / length(years)
  d$reweighted[is.na(d$reweighted)] <- d$DISCWT[is.na(d$reweighted)] / length(years)
  d$separated <- as.integer(d$AGE > 50)
  d$alias <- 2 * d$AGE
  DBI::dbWriteTable(con, "review_rows", d, overwrite = TRUE, temporary = TRUE)
  DBI::dbExecute(con, "CREATE OR REPLACE TEMP VIEW valid AS SELECT * FROM review_rows")
  query <- function(sql) DBI::dbGetQuery(con, sql)
  glm <- function(y, x, family = "gaussian", domain = NULL, weight = "DISCWT") {
    sql <- taylor_glm(query, y, c("(Intercept)" = "1.0", stats::setNames(x, x)),
      family, domain %||% "true", weight = weight)
    ref <- d
    ref$DISCWT <- ref[[weight]]
    design <- reference_design(ref)
    if (!is.null(domain)) design <- subset(design, eval(str2lang(domain), design$variables))
    fit <- survey::svyglm(stats::reformulate(x, y), design,
      family = get(family, asNamespace("stats"))())
    differences(sql, list(estimate = coef(fit), se = survey::SE(fit),
      vcov = vcov(fit), df = fit$df.residual, iterations = fit$iter))
  }
  metric <- function(y, weight = "DISCWT", domain = NULL, na.rm = TRUE) {
    sql_domain <- gsub("&", "AND", domain %||% "true", fixed = TRUE)
    sql <- taylor_stat(query, y, domain = sql_domain, na.rm = na.rm, weight = weight)
    ref <- d
    ref$DISCWT <- ref[[weight]]
    design <- reference_design(ref)
    if (!is.null(domain)) design <- subset(design, eval(str2lang(domain), design$variables))
    if (y == "shifted_y") design$variables$shifted_y <- design$variables$shifted_y - 1e12
    fit <- suppressWarnings(survey::svymean(stats::reformulate(y), design, na.rm = na.rm))
    differences(sql, list(estimate = coef(fit) + if (y == "shifted_y") 1e12 else 0,
      se = stats::setNames(as.numeric(survey::SE(fit)), y)))
  }
  fails <- function(expr, pattern) {
    error <- tryCatch({force(expr); ""}, error = conditionMessage)
    c(estimate = if (grepl(pattern, error, ignore.case = TRUE)) 0 else Inf,
      se = 0, vcov = 0, df = 0, iterations = 0)
  }
  previous <- options(survey.lonely.psu = "adjust", survey.adjust.domain.lonely = TRUE)
  on.exit(options(previous))
  results <- list(
    dollars = glm("dollars", c("AGE", "FEMALE")),
    large_weights = glm("DIED", c("AGE", "FEMALE"), "quasibinomial", weight = "inflated"),
    domain_inf = glm("LOS", c("guarded", "FEMALE"), domain = "YEAR > 2018"),
    reweighted = glm("DIED", c("AGE", "FEMALE"), "quasibinomial", weight = "reweighted"),
    large_offset = metric("shifted_y"),
    domain_lonely = metric("LOS", domain = "AGE >= 65 & FEMALE == 1"),
    nan_expression = differences(taylor_stat(query, "CASE WHEN HOSP_NIS = 2 THEN 'NaN'::DOUBLE ELSE LOS END"),
      {f <- survey::svymean(~LOS, reference_design(d), na.rm = TRUE)
       list(estimate = setNames(coef(f), "CASE WHEN HOSP_NIS = 2 THEN 'NaN'::DOUBLE ELSE LOS END"),
         se = setNames(as.numeric(survey::SE(f)), "CASE WHEN HOSP_NIS = 2 THEN 'NaN'::DOUBLE ELSE LOS END"))}),
    rank_deficient = fails(glm("LOS", c("AGE", "alias")), "rank deficient"),
    separation = fails(glm("separated", "AGE", "quasibinomial"), "separat"),
    nonconvergence = fails(taylor_glm(query, "DIED", c("(Intercept)" = "1", AGE = "AGE"),
      "quasibinomial", maxit = 1L), "converge")
  )
  d$NIS_STRATUM[d$HOSP_NIS == 1L] <- 999L
  DBI::dbWriteTable(con, "review_rows", d, overwrite = TRUE, temporary = TRUE)
  results$sample_lonely_adjust <- metric("LOS")
  options(survey.lonely.psu = "fail")
  results$sample_lonely_fail_missing <- fails(metric("LOS", na.rm = FALSE), "one PSU")
  results
}
