performance_open <- function(path, years) {
  query <- withCallingHandlers(
    easyNIS::nis_open(path, years = years),
    easynis_release_check_failed = function(cnd) stop(cnd$message),
    easynis_release_mismatch = function(cnd) invokeRestart("muffleWarning")
  )
  stopifnot(inherits(query, "tbl_sql"))
  query
}

performance_cohort <- function(query) {
  easyNIS::nis_flag_dx(query, heart_failure = "I50")
}

performance_design <- function(query, whole_sample) {
  if (whole_sample) {
    return(easyNIS::nis_design(query, cohort = TRUE, keep = c(AGE, FEMALE, DIED, LOS)))
  }
  easyNIS::nis_design(query, cohort = heart_failure, keep = c(AGE, FEMALE, DIED, LOS))
}

performance_glm <- function(design) {
  result <- survey::svyglm(DIED ~ AGE + FEMALE + factor(YEAR), design, family = stats::quasibinomial())
  stopifnot(isTRUE(result$converged), all(is.finite(stats::coef(result))))
}

performance_operation <- function(step, path, query, design, years, rows) {
  switch(
    step,
    open_1 = performance_open(path, tail(years, 1L)),
    open_5 = performance_open(path, tail(years, 5L)),
    cohort = {
      count <- performance_cohort(query) |>
        dplyr::filter(heart_failure) |>
        dplyr::summarise(n = dplyr::n()) |>
        dplyr::collect()
      stopifnot(count$n > 0, is.na(rows) || count$n == 5 * sum((rows + 299:297) %/% 300))
    },
    design = stopifnot(inherits(performance_design(query, FALSE), "survey.design")),
    mean_by = {
      mean <- survey::svymean(~LOS, design, na.rm = TRUE)
      groups <- survey::svyby(~LOS, ~FEMALE, design, survey::svymean, na.rm = TRUE)
      stopifnot(all(is.finite(stats::coef(mean))), nrow(groups) == 2L)
    },
    glm = performance_glm(design),
    table = {
      table <- gtsummary::tbl_svysummary(
        design,
        by = FEMALE,
        include = c(AGE, LOS, DIED),
        statistic = list(gtsummary::all_continuous() ~ "{mean} ({sd})")
      )
      stopifnot(inherits(table, "tbl_svysummary"), nrow(table$table_body) >= 3L)
    },
    whole_sample = performance_glm(performance_design(query, TRUE)),
    stop("Unknown performance step")
  )
}

performance_trial <- function(step, path, years, rows, threads, memory, scratch) {
  options(
    survey.lonely.psu = "adjust",
    easyNIS.duckdb_config = list(
      threads = threads,
      memory_limit = memory,
      temp_directory = scratch,
      max_temp_directory_size = "16 GB"
    )
  )
  query <- design <- NULL
  if (!startsWith(step, "open_")) {
    query <- performance_open(path, if (step == "whole_sample") years else tail(years, 5L))
  }
  if (step %in% c("design", "mean_by", "glm", "table")) {
    query <- performance_cohort(query)
  }
  if (step %in% c("mean_by", "glm", "table")) {
    design <- performance_design(query, FALSE)
  }
  started <- proc.time()[["elapsed"]]
  result <- performance_operation(step, path, query, design, years, rows)
  wall <- proc.time()[["elapsed"]] - started
  if (startsWith(step, "open_")) {
    query <- result
  }
  con <- dbplyr::remote_con(query)
  settings <- DBI::dbGetQuery(
    con,
    "SELECT current_setting('threads') AS threads, current_setting('memory_limit') AS memory"
  )
  stopifnot(settings$threads == threads, settings$memory == sub(" ", ".0 ", memory, fixed = TRUE))
  wall
}
