#' @exportS3Method survey::svymean
svymean.nis_survey <- function(x, design, na.rm = FALSE, ..., deff = FALSE, influence = FALSE) {
  nis_survey_stat(x, design, "mean", na.rm, deff, influence, ...)
}

#' @exportS3Method survey::svytotal
svytotal.nis_survey <- function(x, design, na.rm = FALSE, ..., deff = FALSE, influence = FALSE) {
  nis_survey_stat(x, design, "total", na.rm, deff, influence, ...)
}

nis_survey_stat <- function(formula, design, statistic, na.rm, deff, influence, ...) {
  nis_survey_no_dots(...)
  if (!identical(deff, FALSE) || !identical(influence, FALSE)) {
    nis_survey_unsupported("Design effects and discharge influence functions")
  }
  stats <- nis_survey_sums(design, formula, statistic, na.rm)
  scores <- nis_survey_scores(stats$data, stats$labels, statistic, na.rm)
  variance <- nis_survey_variance(scores$u, scores$psu, stats$roster)
  structure(scores$estimate, var = variance, statistic = statistic, class = "svystat")
}

nis_survey_outcome <- function(design, source, type, variable, label, alias) {
  if (!nis_survey_is_factor(variable) && !grepl("^(BOOLEAN|VARCHAR|ENUM)", type)) {
    return(stats::setNames(nis_survey_numeric(alias), label))
  }
  levels <- if (identical(type, "BOOLEAN")) {
    c(FALSE, TRUE)
  } else {
    values <- nis_survey_get(
      design,
      sprintf("SELECT DISTINCT %s AS value FROM %s WHERE inside AND %s IS NOT NULL", alias, source, alias)
    )$value
    if (is.factor(values)) levels(values) else sort(values)
  }
  con <- dbplyr::remote_con(design$query)
  values <- if (is.logical(levels)) as.character(levels) else DBI::dbQuoteLiteral(con, levels)
  stats::setNames(sprintf("CAST(%s = %s AS DOUBLE)", alias, values), paste0(label, levels, recycle0 = TRUE))
}

nis_survey_sums <- function(design, formula, statistic, na.rm, by = NULL) {
  nis_survey_policy()
  outcomes <- nis_survey_formula(formula)
  groups <- if (is.null(by)) list() else nis_survey_formula(by)
  y <- paste0("y", seq_along(outcomes))
  g <- paste0("g", seq_along(groups), recycle0 = TRUE)
  query <- nis_survey_project(
    design,
    c(
      stats::setNames(nis_survey_quos(outcomes, formula), y),
      stats::setNames(nis_survey_quos(groups, by), g)
    )
  )
  types <- nis_survey_types(design, query)
  source <- nis_survey_sql(query)
  labels <- vapply(outcomes, deparse1, character(1))
  outcomes_sql <- unlist(lapply(seq_along(y), function(i) {
    nis_survey_outcome(design, source, types[[y[i]]], outcomes[[i]], labels[i], y[i])
  }))
  if (!length(outcomes_sql)) {
    nis_survey_unsupported("Estimation without any outcome levels")
  }
  roster <- nis_survey_roster(design)
  data <- nis_survey_aggregate(design, source, outcomes_sql, g, statistic, na.rm)
  if (any(data$bad_w > 0)) {
    cli::cli_abort("Analysis weights must be finite and positive.")
  }
  data$psu <- vctrs::vec_match(data[.nis_survey_keys], roster[.nis_survey_keys])
  group_keys <- data[g]
  for (i in seq_along(g)) {
    if (nis_survey_is_factor(groups[[i]])) {
      group_keys[[i]] <- factor(group_keys[[i]])
    }
  }
  names(group_keys) <- vapply(groups, deparse1, character(1))
  domain_psu <- if (length(g)) {
    rows <- nis_survey_get(
      design,
      sprintf(
        "SELECT DISTINCT %s FROM %s WHERE inside",
        paste(.nis_survey_keys, collapse = ", "),
        source
      )
    )
    vctrs::vec_match(rows, roster[.nis_survey_keys])
  }
  list(data = data, roster = roster, labels = names(outcomes_sql), groups = group_keys, domain_psu = domain_psu)
}

nis_survey_aggregate <- function(design, source, outcomes, groups, statistic, na.rm) {
  n <- length(outcomes)
  x <- paste0("x", seq_len(n))
  weights <- nis_survey_numeric("w")
  keys <- paste(c(.nis_survey_keys, groups), collapse = ", ")
  not_missing <- paste(sprintf("%s IS NOT NULL", x), collapse = " AND ")
  usable <- if (na.rm) not_missing else "TRUE"
  inside <- paste(c("inside", sprintf("%s IS NOT NULL", groups)), collapse = " AND ")
  projection <- paste(sprintf("%s AS %s", outcomes, x), collapse = ", ")
  aggregate <- sprintf("coalesce(fsum(weight * %s) FILTER (WHERE %s), 0) AS t%d", x, usable, seq_len(n))
  if (statistic == "mean") {
    centers <- paste(sprintf("coalesce(favg(%1$s), 0) AS a%2$d", x, seq_len(n)), collapse = ", ")
    anchor <- sprintf("SELECT %s FROM rows", centers)
    join <- "CROSS JOIN centers"
    if (length(groups)) {
      grouping <- paste(groups, collapse = ", ")
      anchor <- sprintf("SELECT %s, %s FROM rows GROUP BY %s", grouping, centers, grouping)
      join <- sprintf("JOIN centers USING (%s)", grouping)
    }
    aggregate <- c(
      sprintf("any_value(a%d) AS a%d", seq_len(n), seq_len(n)),
      sprintf("coalesce(fsum(weight * (%s - a%d)) FILTER (WHERE %s), 0) AS t%d", x, seq_len(n), usable, seq_len(n))
    )
  } else {
    anchor <- "SELECT 1"
    join <- ""
  }
  observed <- sprintf("count(%s) AS n%d", x, seq_len(n))
  nis_survey_get(
    design,
    sprintf(
      paste(
        "WITH rows AS NOT MATERIALIZED (SELECT %s, %s AS weight, %s FROM %s WHERE %s),",
        "centers AS (%s)",
        "SELECT %s, count(*) AS domain_n, count(*) FILTER (WHERE %s) AS complete_n,",
        "count(*) FILTER (WHERE weight IS NULL OR NOT isfinite(weight) OR weight <= 0) AS bad_w,",
        "coalesce(fsum(weight) FILTER (WHERE %s), 0) AS weight, %s",
        "FROM rows %s GROUP BY %s"
      ),
      keys,
      weights,
      projection,
      source,
      inside,
      anchor,
      keys,
      not_missing,
      usable,
      paste(c(aggregate, observed), collapse = ", "),
      join,
      keys
    )
  )
}

nis_survey_scores <- function(data, labels, statistic, na.rm) {
  complete <- data$complete_n > 0
  active <- if (na.rm) complete else rep(TRUE, nrow(data))
  n <- length(labels)
  totals <- as.matrix(data[paste0("t", seq_len(n))])
  if (!na.rm) {
    observed <- as.matrix(data[paste0("n", seq_len(n))])
    totals[observed < data$domain_n] <- NA_real_
  }
  estimate <- colSums(totals)
  u <- totals[active, , drop = FALSE]
  if (statistic == "mean" && any(active)) {
    weight <- sum(data$weight)
    estimate <- estimate / weight
    u <- sweep(u, 2L, estimate, function(t, mean) t - data$weight[active] * mean) / weight
    estimate <- estimate + as.numeric(data[1L, paste0("a", seq_len(n))])
  }
  colnames(u) <- labels
  list(estimate = stats::setNames(estimate, labels), u = u, psu = data$psu[active])
}

#' @exportS3Method survey::svyby
svyby.nis_survey <- function(
  formula,
  by,
  design,
  FUN,
  ...,
  na.rm = FALSE,
  covmat = FALSE,
  na.rm.all = FALSE,
  keep.names = TRUE,
  vartype = "se"
) {
  nis_survey_no_dots(...)
  statistic <- if (identical(FUN, survey::svymean)) {
    "mean"
  } else if (identical(FUN, survey::svytotal)) {
    "total"
  }
  if (is.null(statistic)) {
    nis_survey_unsupported("Grouped estimators other than `svymean()` and `svytotal()`")
  }
  if (!identical(vartype, "se")) {
    nis_survey_unsupported("Grouped `vartype` options other than \"se\"")
  }
  if (is.null(by)) {
    nis_survey_unsupported("Grouping without a formula")
  }
  stats <- nis_survey_sums(design, formula, statistic, na.rm, by)
  groups <- stats$groups
  by_factor <- do.call(interaction, groups)
  active <- if (na.rm.all) stats$data$complete_n > 0 else rep(TRUE, nrow(groups))
  idx <- split(seq_len(nrow(groups)), by_factor, drop = TRUE)
  idx <- idx[vapply(idx, function(i) any(active[i]), logical(1))]
  components <- lapply(idx, function(i) {
    nis_survey_scores(stats$data[i, , drop = FALSE], stats$labels, statistic, na.rm)
  })
  nis_survey_group_result(components, idx, groups, stats, covmat, keep.names, statistic)
}

nis_survey_group_result <- function(components, idx, groups, stats, covmat, keep.names, statistic) {
  first <- vapply(idx, `[[`, integer(1), 1L)
  out <- groups[first, , drop = FALSE]
  rownames(out) <- if (keep.names) names(idx) else NULL
  n <- length(stats$labels)
  estimates <- matrix(as.numeric(unlist(lapply(components, `[[`, "estimate"))), ncol = n, byrow = TRUE)
  variances <- lapply(components, function(x) nis_survey_variance(x$u, x$psu, stats$roster))
  errors <- matrix(as.numeric(unlist(lapply(variances, function(v) sqrt(diag(v))))), ncol = n, byrow = TRUE)
  out[stats$labels] <- as.data.frame(estimates)
  se_names <- if (n == 1L) "se" else paste0("se.", stats$labels)
  out[se_names] <- as.data.frame(errors)
  attr(out, "svyby") <- list(
    margins = seq_along(stats$groups),
    nstats = n,
    vars = 1L,
    deffs = FALSE,
    statistic = paste0("svy", statistic),
    variables = stats$labels,
    vartype = "se"
  )
  if (covmat) {
    attr(out, "var") <- nis_survey_group_covariance(components, stats)
  }
  class(out) <- c("svyby", "data.frame")
  out
}

nis_survey_group_covariance <- function(components, stats) {
  psu <- stats$domain_psu
  scores <- lapply(components, function(x) {
    padded <- matrix(0, nrow = length(psu), ncol = length(stats$labels))
    padded[match(x$psu, psu), ] <- x$u
    padded
  })
  if (!length(scores)) {
    return(matrix(numeric(), 0L, 0L))
  }
  u <- do.call(cbind, scores)
  order <- as.vector(t(matrix(seq_len(ncol(u)), nrow = length(stats$labels))))
  nis_survey_variance(u[, order, drop = FALSE], psu, stats$roster)
}
