#' @exportS3Method survey::svyglm
svyglm.nis_survey <- function(
  formula,
  design,
  subset = NULL,
  family = stats::gaussian(),
  ...,
  control = stats::glm.control(),
  rescale = TRUE
) {
  nis_survey_no_dots(...)
  nis_survey_policy()
  family <- nis_survey_family(family, environment(formula))
  if (!missing(subset)) {
    domain <- rlang::enquo(subset)
    if (!rlang::quo_is_null(domain)) {
      design$domain <- c(design$domain, list(domain))
    }
  }
  if (!rlang::is_bool(rescale)) {
    cli::cli_abort("`rescale` must be logical.")
  }
  control <- do.call(stats::glm.control, control)
  input <- nis_survey_model_input(formula, design, family, rescale)
  fit <- nis_survey_irls(design, input, control)
  result <- nis_survey_model_variance(design, input, fit)
  nis_survey_model_result(result, fit, input, family, match.call())
}

nis_survey_family <- function(family, env) {
  if (is.character(family)) {
    family <- get0(family, envir = env, mode = "function")
  }
  if (is.function(family)) {
    family <- family()
  }
  links <- c(gaussian = "identity", binomial = "logit", quasibinomial = "logit", poisson = "log", quasipoisson = "log")
  if (
    !inherits(family, "family") ||
      !identical(unname(links[family$family]), family$link)
  ) {
    nis_survey_unsupported("This GLM family or link")
  }
  family
}

nis_survey_model_input <- function(formula, design, family, rescale) {
  if (!rlang::is_formula(formula, lhs = TRUE)) {
    nis_survey_unsupported("Models without a two-sided formula")
  }
  terms <- stats::terms(formula)
  if (any(attr(terms, "order") != 1L) || length(attr(terms, "offset"))) {
    nis_survey_unsupported("Interactions and offsets")
  }
  variables <- as.list(attr(terms, "variables"))[-1L]
  names <- c("y", paste0("v", seq_len(length(variables) - 1L), recycle0 = TRUE))
  projected <- nis_survey_project(design, stats::setNames(nis_survey_quos(variables, formula), names))
  types <- nis_survey_types(design, projected)[names]
  expressions <- ifelse(types %in% c("DOUBLE", "FLOAT"), paste0("nullif(", names, ", 'NaN'::DOUBLE)"), names)
  fields <- paste(sprintf("%s AS %s", expressions, names), collapse = ", ")
  source <- sprintf(
    "(SELECT %s, %s, %s AS raw_w FROM %s WHERE inside)",
    paste(.nis_survey_keys, collapse = ", "),
    fields,
    nis_survey_numeric("w"),
    nis_survey_sql(projected)
  )
  complete <- paste(sprintf("%s IS NOT NULL", names), collapse = " AND ")
  weights <- nis_survey_get(
    design,
    paste(
      "SELECT favg(raw_w) AS scale,",
      "bool_or(raw_w IS NULL OR NOT isfinite(raw_w) OR raw_w <= 0) AS bad FROM",
      source
    )
  )
  if (isTRUE(weights$bad)) {
    cli::cli_abort("Analysis weights must be finite and positive.")
  }
  if (!is.finite(weights$scale)) {
    cli::cli_abort("No discharges are in the model domain.")
  }
  source <- sprintf("(SELECT * FROM %s WHERE %s)", source, complete)
  model <- nis_survey_model_columns(design, source, variables, names, types, terms, family)
  keys <- paste(.nis_survey_keys, collapse = ", ")
  x <- paste0("x", seq_along(model$sql))
  rows <- sprintf(
    "(SELECT %s, %s AS y, raw_w / %s AS w, %s FROM %s)",
    keys,
    model$response,
    nis_survey_number(if (rescale) weights$scale else 1),
    paste(sprintf("%s AS %s", model$sql, x), collapse = ", "),
    source
  )
  nis_survey_model_scale(design, rows, x, model, family$family, attr(terms, "intercept") == 1L, rescale)
}

nis_survey_model_levels <- function(design, source, name, type) {
  if (identical(type, "BOOLEAN")) {
    return(c(FALSE, TRUE))
  }
  values <- nis_survey_get(design, sprintf("SELECT DISTINCT %1$s AS value FROM %2$s", name, source))$value
  if (is.factor(values)) {
    return(levels(droplevels(values)))
  }
  sort(values)
}

nis_survey_model_columns <- function(design, source, variables, aliases, types, terms, family) {
  labels <- vapply(variables, deparse1, character(1))
  intercept <- attr(terms, "intercept") == 1L
  categorical <- grepl("^(VARCHAR|ENUM)", types) | vapply(variables, nis_survey_is_factor, logical(1))
  logical <- types == "BOOLEAN"
  levels <- lapply(seq_along(aliases), function(i) {
    if (categorical[i] || logical[i]) {
      nis_survey_model_levels(design, source, aliases[i], types[i])
    }
  })
  names(levels) <- labels
  classes <- ifelse(categorical, "factor", ifelse(logical, "logical", "numeric"))
  attr(terms, "dataClasses") <- stats::setNames(classes, labels)
  response <- nis_survey_model_response(design, types[1L], levels[[1L]], categorical[1L], family)
  model <- nis_survey_contrasts(design, aliases[-1L], levels[-1L], labels[-1L], intercept)
  model$response <- response
  model$terms <- terms
  model$skeleton <- stats::setNames(
    lapply(seq_along(classes), function(i) {
      switch(classes[i], factor = factor(levels = levels[[i]]), logical = logical(), numeric = numeric())
    }),
    labels
  )
  model
}

nis_survey_model_response <- function(design, type, levels, categorical, family) {
  if (!categorical) {
    return(nis_survey_numeric("y"))
  }
  if (family$link != "logit" || identical(type, "VARCHAR") || length(levels) != 2L) {
    nis_survey_unsupported("This categorical GLM response")
  }
  literal <- DBI::dbQuoteLiteral(dbplyr::remote_con(design$query), levels[1L])
  sprintf("CAST(y <> %s AS DOUBLE)", literal)
}

nis_survey_contrasts <- function(design, aliases, levels, labels, intercept) {
  factor_terms <- lengths(levels) > 0L
  full <- if (!intercept && any(factor_terms)) which(factor_terms)[1L] else 0L
  con <- dbplyr::remote_con(design$query)
  option <- getOption("contrasts")[1L]
  columns <- lapply(seq_along(aliases), function(i) {
    values <- levels[[i]]
    field <- aliases[i]
    if (is.null(values)) {
      return(stats::setNames(nis_survey_numeric(field), labels[i]))
    }
    if (length(values) < 2L) {
      cli::cli_abort("Rank deficient model matrix. Each factor must have at least two levels.")
    }
    contrasts <- stats::contrasts(factor(values, levels = values), contrasts = i != full)
    literals <- as.character(DBI::dbQuoteLiteral(con, values))
    sql <- apply(contrasts, 2L, function(column) {
      paste("CASE", field, paste("WHEN", literals, "THEN", nis_survey_number(column), collapse = " "), "END")
    })
    suffix <- colnames(contrasts)
    if (is.null(suffix)) {
      suffix <- seq_len(ncol(contrasts))
    }
    stats::setNames(sql, paste0(labels[i], suffix))
  })
  sql <- c(if (intercept) c("(Intercept)" = "1.0::DOUBLE"), unlist(columns))
  if (!length(sql)) {
    nis_survey_unsupported("Models without design-matrix columns")
  }
  list(
    sql = sql,
    assign = c(if (intercept) 0L, rep(seq_along(columns), lengths(columns))),
    contrasts = stats::setNames(as.list(rep(option, sum(factor_terms))), labels[factor_terms]),
    xlevels = lapply(levels[factor_terms], as.character)
  )
}

nis_survey_number <- function(x) {
  sprintf("CAST('%.17g' AS DOUBLE)", x)
}

nis_survey_model_scale <- function(design, rows, x, model, family, intercept, rescale) {
  gaussian <- family == "gaussian"
  logistic <- family %in% c("binomial", "quasibinomial")
  z <- c("y", x)
  info <- nis_survey_model_bounds(design, rows, z, gaussian, logistic, rescale)
  low <- as.numeric(info[paste0("lo_", z)])
  high <- as.numeric(info[paste0("hi_", z)])
  transform <- c(gaussian, seq_along(x) != if (intercept) 1L else 0L)
  center <- ifelse(transform & intercept, low / 2 + high / 2, 0)
  scale <- ifelse(transform & high != low, pmax(abs(high - center), abs(low - center)), 1)
  if (any(!is.finite(scale) | scale <= 0)) {
    cli::cli_abort("Non-finite GLM scaling.")
  }
  scaled <- paste(
    sprintf("((%s - %s) / %s) AS %s", z, nis_survey_number(center), nis_survey_number(scale), z),
    collapse = ", "
  )
  model$rows <- sprintf("(SELECT %s, w, %s FROM %s)", paste(.nis_survey_keys, collapse = ", "), scaled, rows)
  model$x <- x
  model$center <- center
  model$scale <- scale
  model$kind <- if (logistic) {
    "logistic"
  } else if (gaussian) {
    "gaussian"
  } else {
    "poisson"
  }
  model$n <- as.numeric(info$n)
  # The integer ranges bound the number of distinct rows before scaling.
  # Require a substantial reduction and cap the group's double payload at 1 MiB.
  patterns <- prod(high - low + 1)
  model$group_rows <- all(
    isTRUE(info$integral),
    patterns * (length(z) + 1L) <= 2^17,
    model$n >= 16 * patterns
  )
  model
}

nis_survey_model_bounds <- function(design, rows, z, gaussian, logistic, rescale) {
  bounds <- paste(sprintf("min(%1$s) AS lo_%1$s, max(%1$s) AS hi_%1$s", z), collapse = ", ")
  response_bad <- if (gaussian) {
    "false"
  } else if (logistic) {
    "y < 0 OR y > 1"
  } else {
    "y < 0"
  }
  invalid <- paste(c(response_bad, sprintf("NOT isfinite(%s)", z)), collapse = " OR ")
  stats <- c("count(*) AS n", sprintf("bool_or(%s) AS bad", invalid), bounds)
  if (!gaussian && rescale) {
    integral <- paste(sprintf("%1$s = trunc(%1$s)", z), collapse = " AND ")
    stats <- c(stats, sprintf("bool_and(%s) AS integral", integral))
  }
  info <- nis_survey_get(design, sprintf("SELECT %s FROM %s", paste(stats, collapse = ", "), rows))
  if (info$n == 0L || isTRUE(info$bad)) {
    cli::cli_abort("Invalid or empty complete model rows.")
  }
  info
}

nis_survey_cross_terms <- function(columns, weight) {
  pairs <- which(upper.tri(matrix(FALSE, length(columns), length(columns)), diag = TRUE), arr.ind = TRUE)
  paste(sprintf("fsum((%s) * %s * %s)", weight, columns[pairs[, 1L]], columns[pairs[, 2L]]), collapse = ", ")
}

nis_survey_cross_matrix <- function(values, p) {
  out <- matrix(0, p, p)
  out[upper.tri(out, diag = TRUE)] <- as.numeric(values)
  out[lower.tri(out)] <- t(out)[lower.tri(out)]
  out
}

nis_survey_gram_inverse <- function(info, epsilon) {
  norm <- sqrt(diag(info))
  if (any(!is.finite(norm) | norm <= 0)) {
    cli::cli_abort("Rank deficient model matrix. Use `nis_design()` for a row-wise QR fit.")
  }
  scaled <- info / outer(norm, norm)
  # The QR tolerance acts on column norms. Square it for a Gram matrix, with
  # a floor for the precision lost when forming and factoring cross-products.
  qr_tol <- min(1e-7, epsilon / 1000)
  rank_tol <- max(qr_tol^2, 8 * nrow(info) * .Machine$double.eps)
  triangular <- suppressWarnings(chol(scaled, pivot = TRUE, tol = rank_tol))
  # A full-rank Gram matrix can still amplify double-precision rounding
  # beyond eight digits. Refuse the normal-equation solve in that range.
  condition_tol <- .Machine$double.eps / 1e-8
  if (attr(triangular, "rank") < nrow(info) || rcond(scaled) <= condition_tol) {
    cli::cli_abort("Rank deficient or ill-conditioned model matrix. Use `nis_design()` for a row-wise QR fit.")
  }
  order <- order(attr(triangular, "pivot"))
  chol2inv(triangular)[order, order, drop = FALSE] / outer(norm, norm)
}

nis_survey_working <- function(kind, eta) {
  switch(
    kind,
    gaussian = list(mu = eta, d = "1.0::DOUBLE", dev = "pow(y - mu, 2)"),
    logistic = list(
      mu = sprintf(
        "CASE WHEN %1$s > 30 THEN 0.9999999999999998 WHEN %1$s < -30
                    THEN 2.220446049250313e-16 ELSE 1 / (1 + exp(-%1$s)) END",
        eta
      ),
      d = sprintf(
        "CASE WHEN abs(%1$s) > 30 THEN 2.220446049250313e-16
                    ELSE exp(-abs(%1$s)) / pow(1 + exp(-abs(%1$s)), 2) END",
        eta
      ),
      dev = "2 * ((CASE WHEN y > 0 THEN y * ln(y / mu) ELSE 0 END) +
        (CASE WHEN y < 1 THEN (1-y) * ln((1-y)/(1-mu)) ELSE 0 END))"
    ),
    poisson = list(
      mu = sprintf("greatest(2.220446049250313e-16, exp(%s))", eta),
      d = sprintf("greatest(2.220446049250313e-16, exp(%s))", eta),
      dev = "2 * ((CASE WHEN y = 0 THEN 0 ELSE y * ln(y / mu) END) - (y - mu))"
    )
  )
}

nis_survey_eta <- function(input, beta) {
  if (!is.null(beta)) {
    return(paste(input$x, "*", nis_survey_number(beta), collapse = " + "))
  }
  switch(input$kind, gaussian = "y", logistic = "ln((w * y + 0.5) / (w * (1 - y) + 0.5))", poisson = "ln(y + 0.1)")
}

nis_survey_model_system <- function(design, input, beta) {
  working <- nis_survey_working(input$kind, "eta")
  rhs <- paste(sprintf("fsum(%s * w * (d * eta + (y - mu)))", input$x), collapse = ", ")
  query <- sprintf(
    paste(
      "WITH eta_rows AS (SELECT *, %s AS eta FROM %s),",
      "means AS (SELECT *, %s AS mu FROM eta_rows),",
      "working AS (SELECT *, (%s) AS d, CASE WHEN isfinite(mu) AND isfinite(eta)",
      "THEN (%s) ELSE 'Infinity'::DOUBLE END AS dev FROM means)",
      "SELECT %s, %s, fsum(w * dev) AS deviance, max(abs(eta)) AS max_eta,",
      "bool_and(y IN (0, 1) AND ((eta > 0) = (y = 1))) AS perfect FROM working"
    ),
    nis_survey_eta(input, beta),
    input$rows,
    working$mu,
    working$d,
    working$dev,
    nis_survey_cross_terms(input$x, "w * d"),
    rhs
  )
  nis_survey_get(design, query)
}

nis_survey_irls <- function(design, input, control) {
  p <- length(input$x)
  q <- p * (p + 1L) / 2L
  beta <- NULL
  system <- nis_survey_model_system(design, input, beta)
  if (input$group_rows) {
    # The starting eta can depend on each discharge's weight. Later systems
    # are linear in weight for identical outcomes and predictors.
    con <- dbplyr::remote_con(design$query)
    table <- paste0("temp.main.", DBI::dbQuoteIdentifier(con, basename(tempfile("nis_survey_"))))
    columns <- paste(c("y", input$x), collapse = ", ")
    sql <- sprintf("CREATE TEMP TABLE %s AS SELECT %s, fsum(w) AS w FROM %s GROUP BY ALL", table, columns, input$rows)
    DBI::dbExecute(con, sql)
    on.exit(DBI::dbExecute(con, paste("DROP TABLE", table)), add = TRUE)
    input$rows <- table
  }
  for (iteration in seq_len(control$maxit)) {
    inverse <- nis_survey_gram_inverse(nis_survey_cross_matrix(system[seq_len(q)], p), control$epsilon)
    previous <- beta
    beta <- drop(inverse %*% as.numeric(system[q + seq_len(p)]))
    if (!all(is.finite(beta))) {
      cli::cli_abort("IRLS produced non-finite coefficients.")
    }
    if (input$kind == "gaussian") {
      return(list(beta = beta, previous = previous, inverse = inverse, iterations = iteration))
    }
    step <- nis_survey_irls_step(design, input, beta, previous, control$maxit)
    beta <- step$beta
    next_system <- step$system
    dev <- next_system$deviance
    if (input$kind == "logistic" && (isTRUE(next_system$perfect) || next_system$max_eta > 30)) {
      cli::cli_abort("Complete or possible quasi separation in the binomial model.")
    }
    if (abs(dev - system$deviance) / (0.1 + abs(dev)) < control$epsilon) {
      return(list(beta = beta, previous = previous, inverse = inverse, iterations = iteration))
    }
    system <- next_system
  }
  cli::cli_abort("IRLS did not converge.")
}

nis_survey_irls_step <- function(design, input, beta, previous, maxit) {
  system <- nis_survey_model_system(design, input, beta)
  halves <- 0L
  while (!is.finite(system$deviance) && !is.null(previous) && halves < maxit) {
    beta <- (beta + previous) / 2
    system <- nis_survey_model_system(design, input, beta)
    halves <- halves + 1L
  }
  if (!is.finite(system$deviance)) {
    cli::cli_abort("IRLS did not converge after step halving.")
  }
  list(beta = beta, system = system)
}

nis_survey_model_variance <- function(design, input, fit) {
  keys <- paste(.nis_survey_keys, collapse = ", ")
  working <- nis_survey_working(input$kind, "eta")
  prior <- nis_survey_working(input$kind, "prior_eta")
  stats <- sprintf("fsum(%s * score) AS s%d", input$x, seq_along(input$x))
  sql <- sprintf(
    paste(
      "WITH eta_rows AS (SELECT *, %s AS eta, %s AS prior_eta FROM %s),",
      "means AS (SELECT *, %s AS mu FROM eta_rows),",
      "scores AS (SELECT *, w * (%s) * (y - mu) / (%s) AS score FROM means)",
      "SELECT %s, %s, fsum(w * (%s)) AS deviance FROM scores GROUP BY %s"
    ),
    nis_survey_eta(input, fit$beta),
    nis_survey_eta(input, fit$previous),
    input$rows,
    working$mu,
    prior$d,
    working$d,
    keys,
    paste(stats, collapse = ", "),
    working$dev,
    keys
  )
  rows <- nis_survey_get(design, sql)
  roster <- nis_survey_roster(design)
  psu <- vctrs::vec_match(rows[.nis_survey_keys], roster[.nis_survey_keys])
  scores <- as.matrix(rows[paste0("s", seq_along(input$x))])
  u <- scores %*% fit$inverse
  list(
    covariance = nis_survey_variance(u, psu, roster),
    df = length(psu) - length(unique(roster$stratum[psu])) + 1L - length(input$x),
    deviance = sum(rows$deviance)
  )
}

nis_survey_model_result <- function(result, fit, input, family, call) {
  response_scale <- input$scale[1L]
  scales <- response_scale / input$scale[-1L]
  transform <- diag(scales, length(scales))
  offset <- rep(0, length(scales))
  if (attr(input$terms, "intercept") == 1L) {
    transform[1L, ] <- scales * c(1, -input$center[-c(1L, 2L)])
    offset[1L] <- input$center[1L]
  }
  labels <- names(input$sql)
  beta <- stats::setNames(drop(transform %*% fit$beta) + offset, labels)
  covariance <- transform %*% result$covariance %*% t(transform)
  dimnames(covariance) <- list(labels, labels)
  if (!all(is.finite(covariance))) {
    cli::cli_abort("Non-finite model covariance.")
  }
  metadata <- structure(
    matrix(numeric(), 0L, length(labels), dimnames = list(NULL, labels)),
    assign = input$assign,
    contrasts = input$contrasts
  )
  frame <- structure(input$skeleton, class = "data.frame", row.names = integer(), terms = input$terms)
  structure(
    list(
      coefficients = beta,
      cov.unscaled = covariance,
      df.residual = result$df,
      call = call,
      family = family,
      terms = input$terms,
      contrasts = input$contrasts,
      xlevels = input$xlevels,
      rank = length(labels),
      converged = TRUE,
      iter = fit$iterations,
      deviance = result$deviance * response_scale^2,
      n.complete = input$n,
      model = frame,
      matrix = metadata
    ),
    class = c("nis_survey_glm", "svyglm", "glm", "lm")
  )
}
